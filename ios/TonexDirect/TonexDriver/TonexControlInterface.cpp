//
//  TonexControlInterface.cpp
//

#include <os/log.h>
#include <string.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>
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

#include "TonexControlInterface.h"
#include "TonexBridge.h"

#define Log(fmt, ...) os_log(OS_LOG_DEFAULT, "TonexDriver[control] - " fmt, ##__VA_ARGS__)

// Peticiones de clase CDC ACM
static constexpr uint8_t kCDCSetLineCoding       = 0x20;
static constexpr uint8_t kCDCSetControlLineState = 0x22;
// Host→dispositivo | clase | destinatario interfaz
static constexpr uint8_t kRequestTypeClassInterfaceOut = 0x21;

struct TonexControlInterface_IVars
{
    IOUSBHostInterface* interface;
    uint8_t             interfaceNumber;
};

bool TonexControlInterface::init()
{
    if (!super::init()) {
        return false;
    }
    ivars = IONewZero(TonexControlInterface_IVars, 1);
    return ivars != nullptr;
}

void TonexControlInterface::free()
{
    if (ivars != nullptr) {
        OSSafeReleaseNULL(ivars->interface);
    }
    IOSafeDeleteNULL(ivars, TonexControlInterface_IVars, 1);
    super::free();
}

// 115200 baudios, 1 stop bit, sin paridad, 8 bits (como usb_tonex_init) y DTR+RTS.
static void ConfigureLine(IOUSBHostInterface* interface, uint8_t interfaceNumber)
{
    kern_return_t lineCodingResult = kIOReturnError;
    IOBufferMemoryDescriptor* buffer = nullptr;
    kern_return_t ret = interface->CreateIOBuffer(kIOMemoryDirectionInOut, 7, &buffer);
    if (ret != kIOReturnSuccess || buffer == nullptr) {
        Log("CreateIOBuffer falló: 0x%x", ret);
        return;
    }

    IOAddressSegment segment = {};
    ret = buffer->GetAddressRange(&segment);
    if (ret == kIOReturnSuccess && segment.address != 0) {
        const uint32_t baud = 115200;
        uint8_t* p = reinterpret_cast<uint8_t*>(segment.address);
        p[0] = baud & 0xFF;
        p[1] = (baud >> 8) & 0xFF;
        p[2] = (baud >> 16) & 0xFF;
        p[3] = (baud >> 24) & 0xFF;
        p[4] = 0;   // bCharFormat: 1 stop bit
        p[5] = 0;   // bParityType: ninguna
        p[6] = 8;   // bDataBits

        uint16_t transferred = 0;
        ret = interface->DeviceRequest(kRequestTypeClassInterfaceOut, kCDCSetLineCoding,
                                       0, interfaceNumber, 7, buffer, &transferred, 1000);
        Log("SET_LINE_CODING: 0x%x", ret);
        lineCodingResult = ret;
    }
    OSSafeReleaseNULL(buffer);

    uint16_t transferred = 0;
    ret = interface->DeviceRequest(kRequestTypeClassInterfaceOut, kCDCSetControlLineState,
                                   0x0003 /* DTR | RTS */, interfaceNumber, 0, nullptr, &transferred, 1000);
    Log("SET_CONTROL_LINE_STATE: 0x%x", ret);
    TonexBridge::RecordControl(lineCodingResult, ret);
}

kern_return_t IMPL(TonexControlInterface, Start)
{
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) {
        Log("super::Start falló: 0x%x", ret);
        return ret;
    }

    ivars->interface = OSDynamicCast(IOUSBHostInterface, provider);
    if (ivars->interface == nullptr) {
        Log("el proveedor no es IOUSBHostInterface");
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

    const IOUSBConfigurationDescriptor* config = ivars->interface->CopyConfigurationDescriptor();
    const IOUSBInterfaceDescriptor* desc = config ? ivars->interface->GetInterfaceDescriptor(config) : nullptr;
    if (desc != nullptr) {
        ivars->interfaceNumber = desc->bInterfaceNumber;
        Log("interfaz %u clase %02x/%02x/%02x", desc->bInterfaceNumber,
            desc->bInterfaceClass, desc->bInterfaceSubClass, desc->bInterfaceProtocol);
    }
    if (config != nullptr) {
        IOUSBHostFreeDescriptor(config);
    }

    // Si estas peticiones fallan, seguimos: el ESP32 también solo lo registra en el log.
    ConfigureLine(ivars->interface, ivars->interfaceNumber);

    RegisterService();
    return kIOReturnSuccess;
}

kern_return_t IMPL(TonexControlInterface, Stop)
{
    if (ivars->interface != nullptr) {
        ivars->interface->Close(this, 0);
    }
    return Stop(provider, SUPERDISPATCH);
}
