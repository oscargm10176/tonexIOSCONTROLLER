//
//  TonexUserClient.cpp
//
//  Usa una tabla IOUserClientMethodDispatch (el patrón de Apple): el framework valida los
//  tamaños de cada llamada y después invoca el handler.
//

#include <os/log.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOUserClient.h>
#include <DriverKit/OSData.h>

#include "TonexUserClient.h"
#include "TonexBridge.h"
#include "TonexShared.h"

#define Log(fmt, ...) os_log(OS_LOG_DEFAULT, "TonexDriver[client] - " fmt, ##__VA_ARGS__)

struct TonexUserClient_IVars
{
    uint32_t calls;
};

// Las llamadas de un user client se atienden en serie en su cola: un buffer basta.
static uint8_t sReadBuffer[kTonexMaxTransfer];

// MARK: Handlers

static kern_return_t HandleWrite(OSObject* target, void* reference, IOUserClientMethodArguments* arguments)
{
    OSData* input = arguments->structureInput;
    if (input == nullptr || input->getLength() == 0 || input->getLength() > kTonexMaxTransfer) {
        Log("write: entrada inválida");
        return kIOReturnBadArgument;
    }
    kern_return_t ret = TonexBridge::Write(static_cast<const uint8_t*>(input->getBytesNoCopy()),
                                           static_cast<uint32_t>(input->getLength()));
    if (ret != kIOReturnSuccess) {
        Log("write de %u bytes falló: 0x%x", static_cast<uint32_t>(input->getLength()), ret);
    }
    return ret;
}

static kern_return_t HandleRead(OSObject* target, void* reference, IOUserClientMethodArguments* arguments)
{
    uint64_t max = arguments->structureOutputMaximumSize;
    if (max > kTonexMaxTransfer) {
        max = kTonexMaxTransfer;
    }
    uint32_t n = TonexBridge::PopReceived(sReadBuffer, static_cast<uint32_t>(max));
    arguments->scalarOutput[0] = n;
    arguments->scalarOutputCount = 1;
    if (n > 0) {
        arguments->structureOutput = OSData::withBytes(sReadBuffer, n);
        if (arguments->structureOutput == nullptr) {
            return kIOReturnNoMemory;
        }
    }
    return kIOReturnSuccess;
}

static kern_return_t HandleStatus(OSObject* target, void* reference, IOUserClientMethodArguments* arguments)
{
    TonexBridge::Status(arguments->scalarOutput, kTonexStatusCount);
    arguments->scalarOutputCount = kTonexStatusCount;
    return kIOReturnSuccess;
}

static const IOUserClientMethodDispatch sMethods[3] = {
    // kTonexSelectorWrite: struct de entrada variable, sin salida
    {
        .function = &HandleWrite,
        .checkCompletionExists = false,
        .checkScalarInputCount = 0,
        .checkStructureInputSize = kIOUserClientVariableStructureSize,
        .checkScalarOutputCount = 0,
        .checkStructureOutputSize = 0,
    },
    // kTonexSelectorRead: 1 escalar (bytes) + struct de salida variable
    {
        .function = &HandleRead,
        .checkCompletionExists = false,
        .checkScalarInputCount = 0,
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = 1,
        .checkStructureOutputSize = kIOUserClientVariableStructureSize,
    },
    // kTonexSelectorStatus: 4 escalares
    {
        .function = &HandleStatus,
        .checkCompletionExists = false,
        .checkScalarInputCount = 0,
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = kTonexStatusCount,
        .checkStructureOutputSize = 0,
    },
};

// MARK: Ciclo de vida

bool TonexUserClient::init()
{
    if (!super::init()) {
        return false;
    }
    ivars = IONewZero(TonexUserClient_IVars, 1);
    return ivars != nullptr;
}

void TonexUserClient::free()
{
    IOSafeDeleteNULL(ivars, TonexUserClient_IVars, 1);
    super::free();
}

kern_return_t IMPL(TonexUserClient, Start)
{
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    Log("app conectada: 0x%x", ret);
    return ret;
}

kern_return_t IMPL(TonexUserClient, Stop)
{
    Log("app desconectada");
    return Stop(provider, SUPERDISPATCH);
}

kern_return_t TonexUserClient::ExternalMethod(uint64_t selector,
                                              IOUserClientMethodArguments* arguments,
                                              const IOUserClientMethodDispatch* dispatch,
                                              OSObject* target,
                                              void* reference)
{
    if (selector < sizeof(sMethods) / sizeof(sMethods[0])) {
        dispatch = &sMethods[selector];
        if (target == nullptr) {
            target = this;
        }
    }
    kern_return_t ret = super::ExternalMethod(selector, arguments, dispatch, target, reference);
    if (ret != kIOReturnSuccess && selector != kTonexSelectorWrite) {
        Log("selector %llu devolvió 0x%x", selector, ret);
    }
    return ret;
}
