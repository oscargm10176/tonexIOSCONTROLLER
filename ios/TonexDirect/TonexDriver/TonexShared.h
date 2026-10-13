//
//  TonexShared.h
//  Constantes compartidas entre el driver (dext) y la app.
//  La app las replica en Swift en TonexDriverConnection.swift: si cambias algo aquí, cámbialo allá.
//

#ifndef TonexShared_h
#define TonexShared_h

// Selectores de IOConnectCallMethod
#define kTonexSelectorWrite   0   // structureInput: bytes a enviar (≤ kTonexMaxTransfer)
#define kTonexSelectorRead    1   // scalarOutput[0] = n; structureOutput: n bytes recibidos
#define kTonexSelectorStatus  2   // scalarOutput: ver kTonexStatus* abajo

#define kTonexMaxTransfer     4096
#define kTonexStatusCount     12

// Índices de scalarOutput en kTonexSelectorStatus
#define kTonexStatusReady          0   // 1 si los pipes están listos
#define kTonexStatusVendor         1
#define kTonexStatusProduct        2
#define kTonexStatusDropped        3   // bytes perdidos por buffer lleno
#define kTonexStatusLastWrite      4   // último kern_return_t de bulk OUT
#define kTonexStatusWrites         5   // escrituras intentadas
#define kTonexStatusLastRead       6   // último status de ReadComplete
#define kTonexStatusReads          7   // lecturas completadas
#define kTonexStatusLineCoding     8   // resultado de SET_LINE_CODING (0xFFFFFFFF = no se ejecutó)
#define kTonexStatusLineState      9   // resultado de SET_CONTROL_LINE_STATE
#define kTonexStatusEndpoints      10  // (IN << 8) | OUT
#define kTonexStatusRetryWrite     11  // resultado del reintento tras ClearStall

#endif /* TonexShared_h */
