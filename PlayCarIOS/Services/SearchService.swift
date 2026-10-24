import Foundation
import MapKit
import Combine

/// Türkiye odaklı POI / adres arama.
/// MKLocalSearchCompleter + MKLocalSearch ile detay çözümü.
final class SearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {

    @Published var query: String = ""
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var isSearching: Bool = false
    @Published var lastError: String?

    private let completer = MKLocalSearchCompleter()
    private var cancellables = Set<AnyCancellable>()

    /// Türkiye sınırlarına kabaca bias: merkez 39.0, 35.0
    var searchRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.0, longitude: 35.0),
        span: MKCoordinateSpan(latitudeDelta: 8.0, longitudeDelta: 8.0)
    )

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
        completer.region = searchRegion

        $query
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self else { return }
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    self.completions = []
                    self.isSearching = false
                } else {
                    self.isSearching = true
                    self.completer.queryFragment = text
                }
            }
            .store(in: &cancellables)
    }

    /// Kullanıcının gerçek konumuna göre bias'ı güncelle.
    /// Pil: her GPS fix'inde bölgeyi oynatma — 400 m'den fazla
    /// uzaklaşınca güncelle, yoksa atla (sonuçlar aynı kalır).
    private var lastBiasCoordinate: CLLocationCoordinate2D?
    func updateRegion(around coordinate: CLLocationCoordinate2D) {
        if let last = lastBiasCoordinate {
            let moved = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if moved < 400 { return }
        }
        lastBiasCoordinate = coordinate
        searchRegion = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5)
        )
        completer.region = searchRegion
    }

    /// Completion -> MKMapItem çözümle.
    func resolve(_ completion: MKLocalSearchCompletion, completion handler: @escaping (MKMapItem?) -> Void) {
        let request = MKLocalSearch.Request(completion: completion)
        request.region = searchRegion
        MKLocalSearch(request: request).start { response, error in
            if let error {
                DispatchQueue.main.async { self.lastError = error.localizedDescription }
                handler(nil)
                return
            }
            handler(response?.mapItems.first)
        }
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.isSearching = false
            // Sorgu bu arada temizlendiyse geç gelen sonuçları gösterme.
            guard !self.query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            self.completions = completer.results
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.lastError = error.localizedDescription
            self.isSearching = false
        }
    }
}
