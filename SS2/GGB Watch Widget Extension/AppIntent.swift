//
//  AppIntent.swift
//  GGB Watch Widget Extension
//
//  Created by Daniel Raffel on 2/1/25.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "GGB Weather Configuration" }
    static var description: IntentDescription { "Configure the Golden Gate Bridge weather widget." }
}
