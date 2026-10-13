//
//  TonexBridge.h
//  Estado compartido dentro del proceso del driver: buffer circular de recepción y pipe
//  de salida. Lo usan TonexDataInterface (USB) y TonexUserClient (app).
//
//  Es C++ normal (no .iig) a propósito: así no hace falta declarar métodos LOCALONLY
//  entre clases y todo vive en el mismo proceso gracias a IOUserServerOneProcess.
//

#ifndef TonexBridge_h
#define TonexBridge_h

#include <stdint.h>
#include <DriverKit/IOReturn.h>

class IOUSBHostPipe;
class IOBufferMemoryDescriptor;

namespace TonexBridge {

/// Reserva el lock. Idempotente. Devuelve false si no hay memoria.
bool Initialize();

/// La interfaz de datos queda lista: guarda (y retiene) el pipe de salida y su buffer.
void Attach(IOUSBHostPipe* outPipe, IOBufferMemoryDescriptor* outBuffer,
            uint8_t* outBytes, uint32_t outCapacity, uint32_t vendorID, uint32_t productID);

/// La interfaz se va (desconexión): suelta el pipe y vacía el buffer.
void Detach();

/// Desde la lectura USB: añade bytes al buffer circular.
void PushReceived(const uint8_t* data, uint32_t length);

/// Desde la app: saca hasta `maxLength` bytes. Devuelve cuántos copió.
uint32_t PopReceived(uint8_t* out, uint32_t maxLength);

/// Desde la app: escribe en el endpoint bulk OUT (bloqueante, con timeout).
kern_return_t Write(const uint8_t* data, uint32_t length);

/// Ver kTonexStatus* en TonexShared.h
void Status(uint64_t* out, uint32_t count);

/// Diagnóstico: resultados de la interfaz de control, lecturas y endpoints.
void RecordControl(kern_return_t lineCoding, kern_return_t lineState);
void RecordRead(kern_return_t status);
void RecordEndpoints(uint8_t inAddress, uint8_t outAddress);

} // namespace TonexBridge

#endif /* TonexBridge_h */
