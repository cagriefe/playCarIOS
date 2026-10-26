import SwiftUI
import MapKit

struct SearchBarView: View {
    @ObservedObject var searchService: SearchService
    var focused: FocusState<Bool>.Binding
    var onSelect: (MKLocalSearchCompletion) -> Void
    var onSave: (MKLocalSearchCompletion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search for a place or address", text: $searchService.query)
                        .focused(focused)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                        .onSubmit { focused.wrappedValue = false }
                    if searchService.isSearching {
                        ProgressView().scaleEffect(0.8)
                    } else if !searchService.query.isEmpty {
                        Button { searchService.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                // Klavye açıkken haritada boşluğa dokunmak klavyeyi kapatmaz
                // (MKMapView dokunmaları yutar). Standart çıkış: Vazgeç.
                if focused.wrappedValue {
                    Button("Cancel") {
                        searchService.query = ""
                        focused.wrappedValue = false
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            if focused.wrappedValue && !searchService.completions.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(searchService.completions, id: \.self) { c in
                            HStack(spacing: 0) {
                                Button {
                                    focused.wrappedValue = false
                                    onSelect(c)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.title).font(.subheadline).foregroundStyle(.primary)
                                        Text(c.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                }
                                .buttonStyle(.plain)
                                // Satır içi favoriye ekle (Maps'teki gibi)
                                Button { onSave(c) } label: {
                                    Image(systemName: "star")
                                        .font(.body)
                                        .foregroundStyle(.yellow)
                                        .frame(width: 44, height: 44)
                                }
                            }
                            if c != searchService.completions.last {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 6)
            }
        }
    }
}
