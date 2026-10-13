import Foundation

/// Índices de parámetros del Tonex (espejo de `source/main/tonex_params.h` de TonexOneController).
/// 0…108 son los del preset en el orden en que el pedal los manda; 110…117 son globales.
enum TonexParam {
    // Noise gate
    static let gatePost = 0, gateEnable = 1, gateThreshold = 2, gateRelease = 3, gateDepth = 4
    // Compresor
    static let compPost = 5, compEnable = 6, compThreshold = 7, compMakeUp = 8, compAttack = 9
    // EQ
    static let eqPost = 10, eqBass = 11, eqBassFreq = 12, eqMid = 13, eqMidQ = 14,
               eqMidFreq = 15, eqTreble = 16, eqTrebleFreq = 17
    // Amp / modelo
    static let ampEnable = 18, ampSW1 = 19, ampGain = 20, ampVolume = 21, ampMix = 22,
               cabUnknown = 23, cabType = 24
    // VIR
    static let virCabModel = 25, virReso = 26, virMic1 = 27, virMic1X = 28, virMic1Z = 29,
               virMic2 = 30, virMic2X = 31, virMic2Z = 32, virBlend = 33
    static let ampPresence = 34, ampDepth = 35
    // Reverb
    static let reverbPosition = 36, reverbEnable = 37, reverbModel = 38
    /// Primer índice del bloque de 4 (time, predelay, color, mix) de cada modelo de reverb.
    static func reverbBlockStart(model: Int) -> Int { 39 + model * 4 }
    // Modulación
    static let modPost = 63, modEnable = 64, modModel = 65
    // Delay
    static let delayPost = 94, delayEnable = 95, delayModel = 96
    static let paramLast = 109
    // Globales
    static let bpm = 110, inputTrim = 111, cabSimBypass = 112, tempoSource = 113,
               tuningReference = 114, bypass = 115, masterVolume = 116, directMonitor = 117
    static let globalLast = 118
}

/// Modelos de la familia (enum de usb_comms.h). Por ahora la app solo habla con el Tonex Pedal.
enum ModellerType: Int {
    case none = 0, tonexOne = 1, tonexPedal = 2, valetonGP5 = 3, tonexOnePlus = 4, tonexPlug = 5

    var displayName: String {
        switch self {
        case .none: return tr("Sin pedal")
        case .tonexOne: return "Tonex One"
        case .tonexPedal: return "Tonex Pedal"
        case .valetonGP5: return "Valeton GP5"
        case .tonexOnePlus: return "Tonex One+"
        case .tonexPlug: return "Tonex Plug"
        }
    }

    var isTonexFamily: Bool {
        switch self {
        case .tonexOne, .tonexPedal, .tonexOnePlus, .tonexPlug: return true
        default: return false
        }
    }
}

/// Cómo se presenta un parámetro en la UI.
enum ParamKind {
    case slider(unit: String, decimals: Int)
    case toggle
    case prePost                 // 0 = Pre, 1 = Post
    case choice([String])        // índice → etiqueta
    case stepper                 // selección numérica sin etiquetas conocidas
}

struct ParamSpec {
    let index: Int
    let label: String
    let kind: ParamKind
}

enum TonexCatalog {
    static let reverbModels = ["Spring 1", "Spring 2", "Spring 3", "Spring 4", "Room", "Plate"]
    static let modulationModels = ["Chorus", "Tremolo", "Phaser", "Flanger", "Rotary"]
    static let delayModels = ["Digital", "Tape"]
    /// 0 = Tone Model, 1 = VIR, 2 = deshabilitado (comentario en tonex_params.c).
    static let cabinetTypes = ["Tone Model", "VIR", "Sin gabinete"]
    static let virMics = ["Condensador", "Dinámico", "Ribbon"]

    private static func s(_ i: Int, _ label: String, _ unit: String = "", _ decimals: Int = 1) -> ParamSpec {
        ParamSpec(index: i, label: label, kind: .slider(unit: unit, decimals: decimals))
    }
    private static func t(_ i: Int, _ label: String) -> ParamSpec { ParamSpec(index: i, label: label, kind: .toggle) }

    // MARK: Bloques fijos

    static let amp: [ParamSpec] = [
        s(TonexParam.ampGain, "Gain"),
        s(TonexParam.ampVolume, "Volumen"),
        s(TonexParam.ampPresence, "Presence"),
        s(TonexParam.ampDepth, "Depth"),
        s(TonexParam.ampMix, "Mix", "%", 0),
    ]

    static let vir: [ParamSpec] = [
        ParamSpec(index: TonexParam.virCabModel, label: "Gabinete", kind: .stepper),
        s(TonexParam.virReso, "Resonancia"),
        ParamSpec(index: TonexParam.virMic1, label: "Mic 1", kind: .choice(virMics)),
        s(TonexParam.virMic1X, "Mic 1 · X"),
        s(TonexParam.virMic1Z, "Mic 1 · Z"),
        ParamSpec(index: TonexParam.virMic2, label: "Mic 2", kind: .choice(virMics)),
        s(TonexParam.virMic2X, "Mic 2 · X"),
        s(TonexParam.virMic2Z, "Mic 2 · Z"),
        s(TonexParam.virBlend, "Blend", "", 0),
    ]

    static let gate: [ParamSpec] = [
        s(TonexParam.gateThreshold, "Threshold", "dB", 0),
        s(TonexParam.gateRelease, "Release", "ms", 0),
        s(TonexParam.gateDepth, "Depth", "dB", 0),
    ]

    static let comp: [ParamSpec] = [
        s(TonexParam.compThreshold, "Threshold", "dB", 0),
        s(TonexParam.compMakeUp, "Make-up", "dB", 0),
        s(TonexParam.compAttack, "Attack", "ms", 0),
    ]

    static let eq: [ParamSpec] = [
        s(TonexParam.eqBass, "Bass"),
        s(TonexParam.eqBassFreq, "Bass freq", "Hz", 0),
        s(TonexParam.eqMid, "Mid"),
        s(TonexParam.eqMidQ, "Mid Q", "", 2),
        s(TonexParam.eqMidFreq, "Mid freq", "Hz", 0),
        s(TonexParam.eqTreble, "Treble"),
        s(TonexParam.eqTrebleFreq, "Treble freq", "Hz", 0),
    ]

    // MARK: Bloques que dependen del modelo seleccionado

    static func reverbParams(model: Int) -> [ParamSpec] {
        let b = TonexParam.reverbBlockStart(model: max(0, min(model, reverbModels.count - 1)))
        return [
            s(b, "Time"),
            s(b + 1, "Pre-delay", "ms", 0),
            s(b + 2, "Color"),
            s(b + 3, "Mix", "%", 0),
        ]
    }

    /// Bloques de modulación: (inicio, parámetros). Sync y subdivisión se añaden aparte.
    static func modulationParams(model: Int) -> (sync: Int, subdivision: Int, params: [ParamSpec]) {
        switch model {
        case 1: // Tremolo 71-76
            return (71, 72, [s(73, "Rate", "Hz", 2), s(74, "Shape"), s(75, "Spread", "%", 0), s(76, "Level")])
        case 2: // Phaser 77-81
            return (77, 78, [s(79, "Rate", "Hz", 2), s(80, "Depth", "%", 0), s(81, "Level")])
        case 3: // Flanger 82-87
            return (82, 83, [s(84, "Rate", "Hz", 2), s(85, "Depth", "%", 0), s(86, "Feedback", "%", 0), s(87, "Level")])
        case 4: // Rotary 88-93
            return (88, 89, [s(90, "Speed", "", 0), s(91, "Radius", "", 0), s(92, "Spread", "%", 0), s(93, "Level")])
        default: // Chorus 66-70
            return (66, 67, [s(68, "Rate", "Hz", 2), s(69, "Depth", "%", 0), s(70, "Level")])
        }
    }

    static func delayParams(model: Int) -> (sync: Int, subdivision: Int, params: [ParamSpec]) {
        let b = model == 1 ? 103 : 97   // Tape : Digital
        return (b, b + 1, [
            s(b + 2, "Time", "ms", 0),
            s(b + 3, "Feedback", "%", 0),
            t(b + 4, "Modo"),
            s(b + 5, "Mix", "%", 0),
        ])
    }

    // MARK: Globales

    static let globals: [ParamSpec] = [
        s(TonexParam.masterVolume, "Master volume", "dB", 1),
        s(TonexParam.inputTrim, "Input trim", "dB", 1),
        s(TonexParam.bpm, "BPM", "", 0),
        s(TonexParam.tuningReference, "Afinación de referencia", "Hz", 0),
        t(TonexParam.cabSimBypass, "Bypass de cab sim"),
        t(TonexParam.directMonitor, "Direct monitor"),
    ]
}
