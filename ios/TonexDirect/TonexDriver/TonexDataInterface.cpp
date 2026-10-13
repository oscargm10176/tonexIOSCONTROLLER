//
//  TonexDataInterface.cpp
//

#include <os/log.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOUserClient.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/OSDictionary.h>
#include <DriverKit/OSNumber.h>
#include <USBDriverKit/IOUSBHostInterface.h>
// Funciones de descriptores (IOUSBGetNextEndpointDescriptor, IOUSBHostFreeDescriptor)
// y constantes (kIOUSBAbortAsynchronous) viven en otros headers de USBDriverKit.
#if __has_include(<USBDriverKit/USBDriverKit.h>)
#include <USBDriverKit/USBDriverKit.h>
#endif
#if __has_include(<USBDriverKit/AppleUSBDescriptorParsing.h>)
#include <USBDriverKit/AppleUSBDescriptorParsing.h>
#endif
#if __has_include(<USBDriverKit/IOUSBHostFamilyDefinitions.h>)
#include <USBDriverKit/IOUSBHostFamilyDefinitions.h>
#endif
#include <USBDriverKit/IOUSBHostPipe.h>

#include "TonexDataInterface.h"
#include "TonexBridge.h"
#include "TonexShared.h"

#define Log(fmt, ...) os_log(OS_LOG_DEFAULT, "TonexDriver[data] - " fmt, ##__VA_ARGS__)

// Múltiplo de 64 y de 512 (el Tonex declara 64 en IN y 512 en OUT).
static constexpr uint32_t kReadSize  = 4096;
static constexpr uint32_t kWriteSize = 4096;
static constexpr uint32_t kMaxConsecutiveErrors = 20;

struct TonexDataInterface_IVars
{
    IOUSBHostInterface*       interface;
    IOUSBHostPipe*            inPipe;
    IOUSBHostPipe*            outPipe;
    IOBufferMemoryDescriptor* inBuffer;
    IOBufferMemoryDescriptor* outBuffer;
    uint8_t*                  inBytes;
    OSAction*                 readAction;
    uint32_t                  errorCount;
    bool                      stopping;
};

bool TonexDataInterface::init()
{
    if (!super::init()) {
        return false;
    }
    ivars = IONewZero(TonexDataInterface_IVars, 1);
    return ivars != nullptr;
}

void TonexDataInterface::free()
{
    if (ivars != nullptr) {
        OSSafeReleaseNULL(ivars->readAction);
        OSSafeReleaseNULL(ivars->inBuffer);
        OSSafeReleaseNULL(ivars->outBuffer);
        OSSafeReleaseNULL(ivars->inPipe);
        OSSafeReleaseNULL(ivars->outPipe);
        OSSafeReleaseNULL(ivars->interface);
    }
    IOSafeDeleteNULL(ivars, TonexDataInterface_IVars, 1);
    super::free();
}

static uint32_t ReadNumberProperty(IOService* service, const char* key)
{
    OSDictionary* props = nullptr;
    uint32_t value = 0;
    if (service->CopyProperties(&props) == kIOReturnSuccess && props != nullptr) {
        OSNumber* n = OSDynamicCast(OSNumber, props->getObject(key));
        if (n != nullptr) {
            value = n->unsigned32BitValue();
        }
    }
    OSSafeReleaseNULL(props);
    return value;
}

kern_return_t IMPL(TonexDataInterface, Start)
{
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) {
        Log("super::Start falló: 0x%x", ret);
        return ret;
    }

    if (!TonexBridge::Initialize()) {
        Stop(provider, SUPERDISPATCH);
        return kIOReturnNoMemory;
    }

    ivars->interface = OSDynamicCast(IOUSBHostInterface, provider);
    if (ivars->interface == nullptr) {
        Stop(provider, SUPERDISPATCH);
        return kIOReturnNoDevice;
    }
    ivars->interface->retain();

    ret = ivars->interface->Open(this, 0, nullptr);
    if (ret != kIOReturnSuccess) {
        Log("Open falló: 0x%x", ret);
        Stop(provider, SUPERDISPATCH);
        return ret;
    }

    // Busca los endpoints bulk de la interfaz (en el Tonex Pedal: 0x87 IN y 0x07 OUT).
    uint8_t inAddress = 0, outAddress = 0;
    const IOUSBConfigurationDescriptor* config = ivars->interface->CopyConfigurationDescriptor();
    const IOUSBInterfaceDescriptor* intf = config ? ivars->interface->GetInterfaceDescriptor(config) : nullptr;
    if (intf != nullptr) {
        Log("interfaz %u clase %02x, %u endpoints", intf->bInterfaceNumber, intf->bInterfaceClass, intf->bNumEndpoints);
        const IOUSBEndpointDescriptor* ep = nullptr;
        while ((ep = IOUSBGetNextEndpointDescriptor(config, intf, reinterpret_cast<const IOUSBDescriptorHeader*>(ep))) != nullptr) {
            const uint8_t type = ep->bmAttributes & 0x03;
            if (type != 0x02) {   // solo bulk
                continue;
            }
            if (ep->bEndpointAddress & 0x80) {
                inAddress = ep->bEndpointAddress;
            } else {
                outAddress = ep->bEndpointAddress;
            }
        }
    }
    if (config != nullptr) {
        IOUSBHostFreeDescriptor(config);
    }

    if (inAddress == 0 || outAddress == 0) {
        Log("no encontré endpoints bulk (IN 0x%02x, OUT 0x%02x)", inAddress, outAddress);
        Stop(provider, SUPERDISPATCH);
        return kIOReturnNotFound;
    }
    Log("endpoints IN 0x%02x OUT 0x%02x", inAddress, outAddress);
    TonexBridge::RecordEndpoints(inAddress, outAddress);

    ret = ivars->interface->CopyPipe(inAddress, &ivars->inPipe);
    if (ret == kIOReturnSuccess) {
        ret = ivars->interface->CopyPipe(outAddress, &ivars->outPipe);
    }
    if (ret == kIOReturnSuccess) {
        ret = ivars->interface->CreateIOBuffer(kIOMemoryDirectionIn, kReadSize, &ivars->inBuffer);
    }
    if (ret == kIOReturnSuccess) {
        ret = ivars->interface->CreateIOBuffer(kIOMemoryDirectionInOut, kWriteSize, &ivars->outBuffer);
    }
    if (ret != kIOReturnSuccess) {
        Log("pipes/buffers fallaron: 0x%x", ret);
        Stop(provider, SUPERDISPATCH);
        return ret;
    }

    IOAddressSegment inSeg = {}, outSeg = {};
    ivars->inBuffer->GetAddressRange(&inSeg);
    ivars->outBuffer->GetAddressRange(&outSeg);
    ivars->inBytes = reinterpret_cast<uint8_t*>(inSeg.address);
    if (ivars->inBytes == nullptr || outSeg.address == 0) {
        Stop(provider, SUPERDISPATCH);
        return kIOReturnNoMemory;
    }

    ret = CreateActionReadComplete(0, &ivars->readAction);
    if (ret != kIOReturnSuccess) {
        Log("CreateActionReadComplete falló: 0x%x", ret);
        Stop(provider, SUPERDISPATCH);
        return ret;
    }

    TonexBridge::Attach(ivars->outPipe, ivars->outBuffer,
                        reinterpret_cast<uint8_t*>(outSeg.address), kWriteSize,
                        ReadNumberProperty(provider, "idVendor"),
                        ReadNumberProperty(provider, "idProduct"));

    ret = ivars->inPipe->AsyncIO(ivars->inBuffer, kReadSize, ivars->readAction, 0);
    if (ret != kIOReturnSuccess) {
        Log("primer AsyncIO falló: 0x%x", ret);
        TonexBridge::Detach();
        Stop(provider, SUPERDISPATCH);
        return ret;
    }

    // Publica el servicio para que la app lo encuentre con IOServiceNameMatching("TonexDataInterface").
    RegisterService();
    Log("listo");
    return kIOReturnSuccess;
}

kern_return_t IMPL(TonexDataInterface, Stop)
{
    ivars->stopping = true;
    TonexBridge::Detach();

    if (ivars->inPipe != nullptr) {
        // Asíncrono: ReadComplete corre en esta misma cola, uno síncrono se bloquearía.
        ivars->inPipe->Abort(kIOUSBAbortAsynchronous, kIOReturnAborted, nullptr);
    }
    if (ivars->interface != nullptr) {
        ivars->interface->Close(this, 0);
    }
    Log("stop");
    return Stop(provider, SUPERDISPATCH);
}

void IMPL(TonexDataInterface, ReadComplete)
{
    TonexBridge::RecordRead(status);
    if (status == kIOReturnSuccess && actualByteCount > 0 && ivars->inBytes != nullptr) {
        TonexBridge::PushReceived(ivars->inBytes, actualByteCount);
    }

    if (ivars->stopping || status == kIOReturnAborted || status == kIOReturnNotAttached
        || status == kIOReturnNoDevice || status == kIOReturnOffline) {
        return;
    }

    if (status != kIOReturnSuccess) {
        if (++ivars->errorCount > kMaxConsecutiveErrors) {
            Log("demasiados errores de lectura (último 0x%x), dejo de leer", status);
            return;
        }
        // Cubre el caso de stall; si no hay stall es inofensivo.
        ivars->inPipe->ClearStall(false);
    } else {
        ivars->errorCount = 0;
    }

    kern_return_t ret = ivars->inPipe->AsyncIO(ivars->inBuffer, kReadSize, ivars->readAction, 0);
    if (ret != kIOReturnSuccess) {
        Log("AsyncIO falló al rearmar: 0x%x", ret);
    }
}

kern_return_t IMPL(TonexDataInterface, NewUserClient)
{
    IOService* client = nullptr;
    kern_return_t ret = Create(this, "UserClientProperties", &client);
    if (ret != kIOReturnSuccess || client == nullptr) {
        Log("Create(UserClientProperties) falló: 0x%x", ret);
        return ret != kIOReturnSuccess ? ret : kIOReturnError;
    }

    *userClient = OSDynamicCast(IOUserClient, client);
    if (*userClient == nullptr) {
        client->release();
        return kIOReturnError;
    }
    return kIOReturnSuccess;
}
