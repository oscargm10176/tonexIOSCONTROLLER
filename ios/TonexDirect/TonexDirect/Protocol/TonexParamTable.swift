import Foundation

/// Un parámetro con su valor actual y rango.
struct ParamValue: Equatable {
    var value: Double
    var min: Double
    var max: Double
    var name: String
}

/// Rangos y valores por defecto de cada parámetro. Antes los mandaba el ESP32 en GETPARAMS;
/// ahora vienen de esta tabla, copiada de `source/main/tonex_params.c` (TonexParameters[]).
/// El orden es el índice: 0…108 parámetros del preset, 109 = LAST, 110…117 globales.
enum TonexParamTable {
    //                         default, min, max, nombre
    private static let rows: [(Double, Double, Double, String)] = [
        // Noise gate 0-4
        (0, 0, 1, "NG POST"), (1, 0, 1, "NG POWER"), (-64, -100, 0, "NG THRESH"),
        (20, 5, 500, "NG REL"), (-60, -100, -20, "NG DEPTH"),
        // Compresor 5-9
        (1, 0, 1, "COMP POST"), (0, 0, 1, "COMP POWER"), (-14, -40, 0, "COMP THRESH"),
        (-12, -30, 10, "COMP GAIN"), (14, 1, 51, "COMP ATTACK"),
        // EQ 10-17
        (0, 0, 1, "EQ POST"), (5, 0, 10, "EQ BASS"), (300, 75, 600, "EQ BFREQ"),
        (5, 0, 10, "EQ MID"), (0.7, 0.2, 3.0, "EQ MIDQ"), (750, 150, 5000, "EQ MFREQ"),
        (5, 0, 10, "EQ TREBLE"), (1900, 1000, 4000, "EQ TFREQ"),
        // Modelo 18-24
        (1, 0, 1, "MDL AMP"), (0, 0, 1, "MDL SW1"), (5, 0, 10, "MDL GAIN"), (5, 0, 10, "MDL VOL"),
        (100, 0, 100, "MDL MIX"), (1, 0, 1, "MDL CABU"), (0, 0, 2, "MDL CAB"),
        // VIR 25-33
        (5, 0, 10, "VIR_CMDL"), (0, 0, 10, "VIR_RESO"), (0, 0, 2, "VIR M1"), (0, 0, 10, "VIR M1X"),
        (0, 0, 10, "VIR M1Z"), (0, 0, 2, "VIR M2"), (0, 0, 2, "VIR M2X"), (0, 0, 10, "VIR M2Z"),
        (0, -100, 100, "VIR BLEND"),
        // 34-35
        (5, 0, 10, "MDL PRE"), (5, 0, 10, "MDL DEP"),
        // Reverb 36-62
        (0, 0, 1, "RVB POS"), (1, 0, 1, "RVB POWER"), (0, 0, 5, "RVB MODEL"),
        (5, 0, 10, "RVB S1 T"), (0, 0, 500, "RVB S1 P"), (0, -10, 10, "RVB S1 C"), (0, 0, 100, "RVB S1 M"),
        (5, 0, 10, "RVB S2 T"), (0, 0, 500, "RVB S2 P"), (0, -10, 10, "RVB S2 C"), (0, 0, 100, "RVB S2 M"),
        (5, 0, 10, "RVB S3 T"), (0, 0, 500, "RVB S3 P"), (0, -10, 10, "RVB S3 C"), (0, 0, 100, "RVB S3 M"),
        (5, 0, 10, "RVB S4 T"), (0, 0, 500, "RVB S4 P"), (0, -10, 10, "RVB S4 C"), (0, 0, 100, "RVB S4 M"),
        (5, 0, 10, "RVB RM T"), (0, 0, 500, "RVB RM P"), (0, -10, 10, "RVB RM C"), (0, 0, 100, "RVB RM M"),
        (5, 0, 10, "RVB PL T"), (0, 0, 500, "RVB PL P"), (0, -10, 10, "RVB PL C"), (0, 0, 100, "RVB PL M"),
        // Modulación 63-93
        (0, 0, 1, "MOD POST"), (0, 0, 1, "MOD POWER"), (0, 0, 4, "MOD MODEL"),
        (0, 0, 1, "MOD CH S"), (0, 0, 17, "MOD CH T"), (0.5, 0.1, 10, "MOD CH R"), (0, 0, 100, "MOD CH D"),
        (0, 0, 10, "MOD CH L"),
        (0, 0, 1, "MOD TR S"), (0, 0, 17, "MOD TR T"), (0.5, 0.1, 10, "MOD TR R"), (0, 0, 10, "MOD TR P"),
        (0, 0, 100, "MOD TR D"), (0, 0, 10, "MOD TR L"),
        (0, 0, 1, "MOD PH S"), (0, 0, 17, "MOD PH T"), (0.5, 0.1, 10, "MOD PH R"), (0, 0, 100, "MOD PH D"),
        (0, 0, 10, "MOD PH L"),
        (0, 0, 1, "MOD FL S"), (0, 0, 17, "MOD FL T"), (0.5, 0.1, 10, "MOD FL R"), (0, 0, 100, "MOD FL D"),
        (0, 0, 100, "MOD FL F"), (0, 0, 10, "MOD FL L"),
        (0, 0, 1, "MOD RO S"), (0, 0, 17, "MOD RO T"), (0, 0, 400, "MOD RO S"), (0, 0, 300, "MOD RO R"),
        (0, 0, 100, "MOD RO D"), (0, 0, 10, "MOD RO L"),
        // Delay 94-108
        (0, 0, 1, "DLY POST"), (0, 0, 1, "DLY POWER"), (0, 0, 1, "DLY MODEL"),
        (0, 0, 1, "DLY DG S"), (0, 0, 17, "DLY DG T"), (0, 0, 1000, "DLY DT M"), (0, 0, 100, "DLY DT F"),
        (0, 0, 1, "DLY DT O"), (0, 0, 100, "DLY DT X"),
        (0, 0, 1, "DLY TA S"), (0, 0, 17, "DLY TA T"), (0, 0, 1000, "DLY TA M"), (0, 0, 100, "DLY TA F"),
        (0, 0, 1, "DLY TA O"), (0, 0, 100, "DLY TA X"),
        // 109
        (0, 0, 0, "LAST"),
        // Globales 110-117
        (80, 40, 240, "BPM"), (0, -15, 15, "TRIM"), (0, 0, 1, "CABSIM"), (0, 0, 1, "TEMPOS"),
        (440, 415, 465, "TUNEREF"), (0, 0, 1, "BYPASS"), (0, -40, 3, "MVOL"), (0, 0, 1, "DIRMON"),
    ]

    /// Valor por defecto de un parámetro (para "doble toque = restablecer").
    static func defaultValue(_ index: Int) -> Double? {
        rows.indices.contains(index) && index != TonexParam.paramLast ? rows[index].0 : nil
    }

    /// Diccionario inicial (valores por defecto) sin la entrada LAST.
    static func defaults() -> [Int: ParamValue] {
        assert(rows.count == TonexParam.globalLast, "La tabla debe tener \(TonexParam.globalLast) filas")
        var out: [Int: ParamValue] = [:]
        for (i, r) in rows.enumerated() where i != TonexParam.paramLast {
            out[i] = ParamValue(value: r.0, min: r.1, max: r.2, name: r.3)
        }
        return out
    }
}
