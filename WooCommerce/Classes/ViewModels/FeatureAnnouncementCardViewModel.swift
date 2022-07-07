import Foundation
import UIKit

private typealias FeatureCardEvent = WooAnalyticsEvent.FeatureCard

struct FeatureAnnouncementCardViewModel {
    private let analytics: Analytics
    private let config: Configuration

    var title: String {
        config.title
    }

    var message: String {
        config.message
    }

    var buttonTitle: String {
        config.buttonTitle
    }

    var image: UIImage {
        config.image
    }

    init(analytics: Analytics,
         configuration: Configuration) {
        self.analytics = analytics
        self.config = configuration
    }

    func onAppear() {
        trackAnnouncementShown()
    }

    func dismissedTapped() {
        trackAnnouncementDismissed()
    }

    func ctaTapped() {
        trackAnnouncementCtaTapped()
    }

    private func trackAnnouncementShown() {
        track(FeatureCardEvent.shown(source: config.source,
                                     campaign: config.campaign))
    }

    private func trackAnnouncementDismissed() {
        track(FeatureCardEvent.dismissed(source: config.source,
                                         campaign: config.campaign))
    }

    private func trackAnnouncementCtaTapped() {
        track(FeatureCardEvent.ctaTapped(source: config.source,
                                         campaign: config.campaign))
    }

    private func track(_ event: WooAnalyticsEvent) {
        analytics.track(event: event)
    }

    struct Configuration {
        let source: WooAnalyticsEvent.FeatureCard.Source
        let campaign: WooAnalyticsEvent.FeatureCard.Campaign
        let title: String
        let message: String
        let buttonTitle: String
        let image: UIImage
    }
}
