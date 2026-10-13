//
//  TonexBridge.cpp
//

#include <os/log.h>
#include <string.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <USBDriverKit/IOUSBHostPipe.h>

#include "TonexBridge.h"
#include "TonexShared.h"

#define Log(fmt, ...) os_log(OS_LOG_DEFAULT, "TonexDriver - " fmt, ##__VA_ARGS__)

namespace {

constexpr uint32_t kRingSize = 128 * 1024;   // ~40 respuestas de preset; la app lee mucho más rápido
constexpr uint32_t kWriteTimeoutMs = 1000;

// POD globales: sin constructores estáticos.
IOLock* gRxLock = nullptr;
IOLock* gTxLock = nullptr;

uint8_t  gRing[kRingSize];
uint32_t gHead = 0;      // siguiente posición de escritura
uint32_t gCount = 0;     // bytes disponibles
uint64_t gOverflow = 0;  // bytes descartados por buffer lleno

IOUSBHostPipe*            gOutPipe = nullptr;
IOBufferMemoryDescriptor* gOutBuffer = nullptr;
uint8_t*                  gOutBytes = nullptr;
uint32_t                  gOutCapacity = 0;
uint32_t                  gVendor = 0;
uint32_t                  gProduct = 0;

// Diagnóstico (valores sueltos; no hace falta lock para leerlos de vez en cuando)
uint32_t gLastWrite = 0;
uint64_t gWrites = 0;
uint32_t gLastRead = 0;
uint64_t gReads = 0;
uint32_t gLineCoding = 0xFFFFFFFF;
uint32_t gLineState = 0xFFFFFFFF;
uint32_t gEndpoints = 0;
uint32_t gRetryWrite = 0xFFFFFFFF;

} // namespace

namespace TonexBridge {

bool Initialize()
{
    if (gRxLock == nullptr) {
        gRxLock = IOLockAlloc();
    }
    if (gTxLock == nullptr) {
        gTxLock = IOLockAlloc();
    }
    return gRxLock != nullptr && gTxLock != nullptr;
}

void Attach(IOUSBHostPipe* outPipe, IOBufferMemoryDescriptor* outBuffer,
            uint8_t* outBytes, uint32_t outCapacity, uint32_t vendorID, uint32_t productID)
{
    if (!Initialize()) {
        return;
    }

    IOLockLock(gTxLock);
    if (outPipe)   { outPipe->retain(); }
    if (outBuffer) { outBuffer->retain(); }
    if (gOutPipe)   { gOutPipe->release(); }
    if (gOutBuffer) { gOutBuffer->release(); }
    gOutPipe = outPipe;
    gOutBuffer = outBuffer;
    gOutBytes = outBytes;
    gOutCapacity = outCapacity;
    gVendor = vendorID;
    gProduct = productID;
    IOLockUnlock(gTxLock);

    IOLockLock(gRxLock);
    gHead = 0;
    gCount = 0;
    gOverflow = 0;
    IOLockUnlock(gRxLock);

    Log("attach %04x:%04x", vendorID, productID);
}

void Detach()
{
    if (!Initialize()) {
        return;
    }

    IOLockLock(gTxLock);
    if (gOutPipe)   { gOutPipe->release(); }
    if (gOutBuffer) { gOutBuffer->release(); }
    gOutPipe = nullptr;
    gOutBuffer = nullptr;
    gOutBytes = nullptr;
    gOutCapacity = 0;
    IOLockUnlock(gTxLock);

    IOLockLock(gRxLock);
    gHead = 0;
    gCount = 0;
    IOLockUnlock(gRxLock);

    Log("detach");
}

void PushReceived(const uint8_t* data, uint32_t length)
{
    if (gRxLock == nullptr || data == nullptr || length == 0) {
        return;
    }

    IOLockLock(gRxLock);
    for (uint32_t i = 0; i < length; i++) {
        if (gCount == kRingSize) {
            // Lleno: se descarta lo nuevo. La app lo detecta con el contador y resincroniza.
            gOverflow += (length - i);
            break;
        }
        gRing[gHead] = data[i];
        gHead = (gHead + 1) % kRingSize;
        gCount++;
    }
    IOLockUnlock(gRxLock);
}

uint32_t PopReceived(uint8_t* out, uint32_t maxLength)
{
    if (gRxLock == nullptr || out == nullptr || maxLength == 0) {
        return 0;
    }

    IOLockLock(gRxLock);
    uint32_t n = gCount < maxLength ? gCount : maxLength;
    uint32_t tail = (gHead + kRingSize - gCount) % kRingSize;
    for (uint32_t i = 0; i < n; i++) {
        out[i] = gRing[(tail + i) % kRingSize];
    }
    gCount -= n;
    IOLockUnlock(gRxLock);
    return n;
}

kern_return_t Write(const uint8_t* data, uint32_t length)
{
    if (gTxLock == nullptr) {
        return kIOReturnNotReady;
    }
    if (data == nullptr || length == 0) {
        return kIOReturnBadArgument;
    }

    kern_return_t ret = kIOReturnSuccess;
    IOLockLock(gTxLock);

    if (gOutPipe == nullptr || gOutBuffer == nullptr || gOutBytes == nullptr) {
        IOLockUnlock(gTxLock);
        return kIOReturnNotAttached;
    }

    uint32_t offset = 0;
    while (offset < length) {
        uint32_t chunk = length - offset;
        if (chunk > gOutCapacity) {
            chunk = gOutCapacity;
        }
        memcpy(gOutBytes, data + offset, chunk);

        uint32_t transferred = 0;
        ret = gOutPipe->IO(gOutBuffer, chunk, &transferred, kWriteTimeoutMs);
        gWrites++;
        gLastWrite = static_cast<uint32_t>(ret);
        if (ret != kIOReturnSuccess) {
            Log("bulk OUT falló: 0x%x (%u bytes); limpio stall y reintento", ret, chunk);
            gOutPipe->ClearStall(true);
            transferred = 0;
            ret = gOutPipe->IO(gOutBuffer, chunk, &transferred, kWriteTimeoutMs);
            gRetryWrite = static_cast<uint32_t>(ret);
            if (ret != kIOReturnSuccess) {
                Log("reintento bulk OUT falló: 0x%x", ret);
                break;
            }
        }
        offset += transferred > 0 ? transferred : chunk;
    }

    IOLockUnlock(gTxLock);
    return ret;
}

void RecordControl(kern_return_t lineCoding, kern_return_t lineState)
{
    gLineCoding = static_cast<uint32_t>(lineCoding);
    gLineState = static_cast<uint32_t>(lineState);
}

void RecordRead(kern_return_t status)
{
    gLastRead = static_cast<uint32_t>(status);
    gReads++;
}

void RecordEndpoints(uint8_t inAddress, uint8_t outAddress)
{
    gEndpoints = (static_cast<uint32_t>(inAddress) << 8) | outAddress;
}

void Status(uint64_t* out, uint32_t count)
{
    if (out == nullptr || count == 0) {
        return;
    }
    uint64_t values[kTonexStatusCount] = {};

    if (gTxLock != nullptr) {
        IOLockLock(gTxLock);
        values[kTonexStatusReady] = gOutPipe != nullptr ? 1 : 0;
        values[kTonexStatusVendor] = gVendor;
        values[kTonexStatusProduct] = gProduct;
        IOLockUnlock(gTxLock);
    }
    if (gRxLock != nullptr) {
        IOLockLock(gRxLock);
        values[kTonexStatusDropped] = gOverflow;
        IOLockUnlock(gRxLock);
    }
    values[kTonexStatusLastWrite] = gLastWrite;
    values[kTonexStatusWrites] = gWrites;
    values[kTonexStatusLastRead] = gLastRead;
    values[kTonexStatusReads] = gReads;
    values[kTonexStatusLineCoding] = gLineCoding;
    values[kTonexStatusLineState] = gLineState;
    values[kTonexStatusEndpoints] = gEndpoints;
    values[kTonexStatusRetryWrite] = gRetryWrite;

    for (uint32_t i = 0; i < count && i < kTonexStatusCount; i++) {
        out[i] = values[i];
    }
}

} // namespace TonexBridge
