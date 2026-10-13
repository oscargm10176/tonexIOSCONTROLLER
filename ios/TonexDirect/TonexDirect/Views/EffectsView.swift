import SwiftUI

/// Edición de la cadena de efectos del preset activo, en el orden del Tonex.
struct EffectsView: View {
    @Environment(ControllerStore.self) private var store

    var body: some View {
        Group {
            Group {
                if store.state == .ready, !store.params.isEmpty {
                    ScrollViewReader { proxy in
                        form
                            .onAppear { scroll(proxy, animated: false) }
                            .onChange(of: store.focusedBlock) { _, _ in scroll(proxy, animated: true) }
                    }
                } else {
                    ContentUnavailableView(
                        "Sin datos del pedal",
                        systemImage: "slider.horizontal.3",
                        description: Text("Conecta el pedal por USB para editar los efectos.")
                    )
                }
            }
            .navigationTitle(store.currentPresetInfo?.name ?? "Efectos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(store.state != .ready)
                }
            }
        }
    }

    private var form: some View {
        let cabType = Int(store.value(TonexParam.cabType).rounded())
        let reverbModel = Int(store.value(TonexParam.reverbModel).rounded())
        let modModel = Int(store.value(TonexParam.modModel).rounded())
        let delayModel = Int(store.value(TonexParam.delayModel).rounded())

        return Form {
            Section {
                HStack { Spacer(); EffectsChainView(); Spacer() }
                    .listRowBackground(Color.clear)
            }

            // Amp
            Section {
                ForEach(TonexCatalog.amp, id: \.index) { ParamRow(spec: $0) }
                ChoicePicker(index: TonexParam.cabType, label: "Gabinete", options: TonexCatalog.cabinetTypes)
            } header: {
                EffectHeader(title: "Amplificador", enableIndex: TonexParam.ampEnable)
            }
            .id(EffectBlock.amp)

            if cabType == 1 {
                Section("Gabinete VIR") {
                    ForEach(TonexCatalog.vir, id: \.index) { ParamRow(spec: $0) }
                }
            }

            // Noise gate
            Section {
                PrePostPicker(index: TonexParam.gatePost, label: "Posición")
                ForEach(TonexCatalog.gate, id: \.index) { ParamRow(spec: $0) }
            } header: {
                EffectHeader(title: "Noise gate", enableIndex: TonexParam.gateEnable)
            }
            .id(EffectBlock.gate)

            // Compresor
            Section {
                PrePostPicker(index: TonexParam.compPost, label: "Posición")
                ForEach(TonexCatalog.comp, id: \.index) { ParamRow(spec: $0) }
            } header: {
                EffectHeader(title: "Compresor", enableIndex: TonexParam.compEnable)
            }
            .id(EffectBlock.comp)

            // EQ
            Section {
                PrePostPicker(index: TonexParam.eqPost, label: "Posición")
                ForEach(TonexCatalog.eq, id: \.index) { ParamRow(spec: $0) }
            } header: {
                EffectHeader(title: "EQ", enableIndex: nil)
            }
            .id(EffectBlock.eq)

            // Modulación
            Section {
                PrePostPicker(index: TonexParam.modPost, label: "Posición")
                ChoicePicker(index: TonexParam.modModel, label: "Tipo", options: TonexCatalog.modulationModels)
                timeBasedParams(TonexCatalog.modulationParams(model: modModel))
            } header: {
                EffectHeader(title: "Modulación", enableIndex: TonexParam.modEnable)
            }
            .id(EffectBlock.mod)

            // Delay
            Section {
                PrePostPicker(index: TonexParam.delayPost, label: "Posición")
                ChoicePicker(index: TonexParam.delayModel, label: "Tipo", options: TonexCatalog.delayModels)
                timeBasedParams(TonexCatalog.delayParams(model: delayModel))
            } header: {
                EffectHeader(title: "Delay", enableIndex: TonexParam.delayEnable)
            }
            .id(EffectBlock.delay)

            // Reverb
            Section {
                PrePostPicker(index: TonexParam.reverbPosition, label: "Posición")
                ChoicePicker(index: TonexParam.reverbModel, label: "Tipo", options: TonexCatalog.reverbModels)
                ForEach(TonexCatalog.reverbParams(model: reverbModel), id: \.index) { ParamRow(spec: $0) }
            } header: {
                EffectHeader(title: "Reverb", enableIndex: TonexParam.reverbEnable)
            }
            .id(EffectBlock.reverb)
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let block = store.focusedBlock else { return }
        if animated {
            withAnimation(.snappy) { proxy.scrollTo(block, anchor: .top) }
        } else {
            proxy.scrollTo(block, anchor: .top)
        }
    }

    /// Sync al tempo + subdivisión (solo si sync está activo) + resto de parámetros.
    @ViewBuilder
    private func timeBasedParams(_ block: (sync: Int, subdivision: Int, params: [ParamSpec])) -> some View {
        ParamRow(spec: ParamSpec(index: block.sync, label: "Sync al tempo", kind: .toggle))
        if store.isOn(block.sync) {
            ParamRow(spec: ParamSpec(index: block.subdivision, label: "Subdivisión", kind: .stepper))
        }
        ForEach(block.params, id: \.index) { ParamRow(spec: $0) }
    }
}
