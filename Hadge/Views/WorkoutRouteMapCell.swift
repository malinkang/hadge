import UIKit
import CoreLocation
import HealthKit
import MapKit

final class WorkoutRouteMapCell: UITableViewCell {
    private let mapView = MKMapView()
    private let pointCountLabel = UILabel()
    private let replayButton = UIButton(type: .system)
    private var routeRenderer: AnimatedRouteOverlayRenderer?
    private var routeColor: UIColor = .systemGreen
    private var hasConfiguredRoute = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func configure(locations: [CLLocation], activityType: HKWorkoutActivityType) {
        guard !hasConfiguredRoute else {
            routeRenderer?.restart()
            return
        }
        hasConfiguredRoute = true

        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        routeColor = Self.color(for: activityType)
        pointCountLabel.text = "\(locations.count) 个轨迹点"

        var coordinates = locations.map(\.coordinate)
        let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
        mapView.addOverlay(polyline)

        if let start = coordinates.first {
            mapView.addAnnotation(RouteEndpointAnnotation(coordinate: start, kind: .start))
        }
        if let end = coordinates.last {
            mapView.addAnnotation(RouteEndpointAnnotation(coordinate: end, kind: .end))
        }

        let bounds = polyline.boundingMapRect
        let horizontalPadding = max(bounds.size.width * 0.16, 500)
        let verticalPadding = max(bounds.size.height * 0.16, 500)
        let paddedBounds = bounds.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        mapView.setVisibleMapRect(
            paddedBounds,
            edgePadding: UIEdgeInsets(top: 58, left: 32, bottom: 58, right: 32),
            animated: false
        )

        DispatchQueue.main.async { [weak self] in
            self?.routeRenderer?.restart()
        }
    }

    private func configureView() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.delegate = self
        mapView.mapType = .standard
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = false
        mapView.showsBuildings = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.layer.cornerRadius = 18
        mapView.layer.cornerCurve = .continuous
        mapView.clipsToBounds = true
        mapView.accessibilityLabel = "运动路线地图"

        pointCountLabel.translatesAutoresizingMaskIntoConstraints = false
        pointCountLabel.textColor = .label
        pointCountLabel.font = .preferredFont(forTextStyle: .caption1)
        pointCountLabel.adjustsFontForContentSizeCategory = true
        pointCountLabel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.88)
        pointCountLabel.layer.cornerRadius = 11
        pointCountLabel.layer.cornerCurve = .continuous
        pointCountLabel.clipsToBounds = true
        pointCountLabel.textAlignment = .center

        replayButton.translatesAutoresizingMaskIntoConstraints = false
        replayButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        replayButton.tintColor = .label
        replayButton.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        replayButton.layer.cornerRadius = 17
        replayButton.layer.cornerCurve = .continuous
        replayButton.accessibilityLabel = "重播路线动画"
        replayButton.addTarget(self, action: #selector(replayRoute), for: .touchUpInside)

        contentView.addSubview(mapView)
        contentView.addSubview(pointCountLabel)
        contentView.addSubview(replayButton)

        NSLayoutConstraint.activate([
            mapView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            mapView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            mapView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            mapView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            pointCountLabel.leadingAnchor.constraint(equalTo: mapView.leadingAnchor, constant: 12),
            pointCountLabel.bottomAnchor.constraint(equalTo: mapView.bottomAnchor, constant: -12),
            pointCountLabel.heightAnchor.constraint(equalToConstant: 24),
            pointCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),

            replayButton.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -12),
            replayButton.bottomAnchor.constraint(equalTo: mapView.bottomAnchor, constant: -12),
            replayButton.widthAnchor.constraint(equalToConstant: 34),
            replayButton.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    @objc private func replayRoute() {
        routeRenderer?.restart()
    }

    private static func color(for activityType: HKWorkoutActivityType) -> UIColor {
        switch activityType {
        case .running:
            return .systemGreen
        case .walking:
            return .systemBlue
        case .cycling, .handCycling:
            return .systemOrange
        case .hiking:
            return .brown
        case .swimming:
            return .systemTeal
        case .wheelchairRunPace, .wheelchairWalkPace:
            return .systemIndigo
        default:
            return .systemPurple
        }
    }
}

extension WorkoutRouteMapCell: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let polyline = overlay as? MKPolyline else {
            return MKOverlayRenderer(overlay: overlay)
        }

        let renderer = AnimatedRouteOverlayRenderer(
            polyline: polyline,
            color: routeColor
        )
        routeRenderer = renderer
        DispatchQueue.main.async {
            renderer.restart()
        }
        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let endpoint = annotation as? RouteEndpointAnnotation else {
            return nil
        }

        let identifier = "RouteEndpoint"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            as? MKMarkerAnnotationView
            ?? MKMarkerAnnotationView(annotation: endpoint, reuseIdentifier: identifier)
        view.annotation = endpoint
        view.canShowCallout = false
        view.displayPriority = .required
        view.collisionMode = .circle
        view.glyphText = endpoint.kind.glyph
        view.markerTintColor = endpoint.kind.color
        return view
    }
}

private final class RouteEndpointAnnotation: NSObject, MKAnnotation {
    enum Kind {
        case start
        case end

        var title: String {
            switch self {
            case .start: return "起点"
            case .end: return "终点"
            }
        }

        var glyph: String {
            switch self {
            case .start: return "起"
            case .end: return "终"
            }
        }

        var color: UIColor {
            switch self {
            case .start: return .systemGreen
            case .end: return .systemRed
            }
        }
    }

    let coordinate: CLLocationCoordinate2D
    let kind: Kind
    var title: String? { kind.title }

    init(coordinate: CLLocationCoordinate2D, kind: Kind) {
        self.coordinate = coordinate
        self.kind = kind
    }
}

private final class AnimatedRouteOverlayRenderer: MKOverlayRenderer {
    private let routeColor: UIColor
    private var progress: CGFloat = 0
    private var displayLink: CADisplayLink?
    private var animationStartedAt: CFTimeInterval = 0
    private let animationDuration: CFTimeInterval = 2.4

    init(polyline: MKPolyline, color: UIColor) {
        self.routeColor = color
        super.init(overlay: polyline)
    }

    deinit {
        displayLink?.invalidate()
    }

    func restart() {
        displayLink?.invalidate()
        displayLink = nil

        if UIAccessibility.isReduceMotionEnabled {
            progress = 1
            setNeedsDisplay()
            return
        }

        progress = 0
        animationStartedAt = 0
        let link = CADisplayLink(target: self, selector: #selector(updateAnimation))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        displayLink = link
        setNeedsDisplay()
    }

    @objc private func updateAnimation(_ link: CADisplayLink) {
        if animationStartedAt == 0 {
            animationStartedAt = link.timestamp
        }
        let elapsed = link.timestamp - animationStartedAt
        let linear = min(max(elapsed / animationDuration, 0), 1)
        let eased = linear * linear * (3 - 2 * linear)
        progress = CGFloat(eased)
        setNeedsDisplay()

        if linear >= 1 {
            displayLink?.invalidate()
            displayLink = nil
            progress = 1
            setNeedsDisplay()
        }
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let polyline = overlay as? MKPolyline, polyline.pointCount > 1 else {
            return
        }

        let points = polyline.points()
        let visibleCount = max(
            2,
            min(
                polyline.pointCount,
                Int(ceil(CGFloat(polyline.pointCount - 1) * max(progress, 0.01))) + 1
            )
        )
        guard visibleCount > 1 else { return }

        let path = CGMutablePath()
        path.move(to: point(for: points[0]))
        for index in 1..<visibleCount {
            path.addLine(to: point(for: points[index]))
        }

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.addPath(path)
        context.setStrokeColor(UIColor.systemBackground.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(8 / zoomScale)
        context.strokePath()

        context.addPath(path)
        context.setStrokeColor(routeColor.cgColor)
        context.setLineWidth(5 / zoomScale)
        context.strokePath()
        context.restoreGState()
    }
}
