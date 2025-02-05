# Goal and Testing Considerations

Our primary goal is to ensure that the watchOS widget displays the current weather data and a background image of the bridge, sourced from the iPhone’s cached data.

Since we are running the watchOS simulator, we need to ensure that upon first installation of the widget (while there is internet connectivity), the widget immediately updates from the cache rather than waiting for the next data refresh interval (which could be up to 15 minutes). This will allow us to verify that the implementation is working without long delays during testing.

# Background Issue

WidgetKit does not allow direct network requests from the widget extension, affecting both weather API calls and image loading. As a result:
	•	The watchOS widget currently shows placeholder data instead of actual weather.
	•	The bridge background image does not load in the watchOS widget.

# Solution Approach

We need to modify the architecture to handle data fetching and caching properly:
	1.	Move all watchOS network requests to the main iOS app.
	2.	Cache weather data and the bridge image on iOS when making network requests.
	3.	Store the cached data in a shared app group container.
	4.	Modify the watchOS widget to read from this cached data.
	5.	Ensure watchOS and iOS apps are accessing the same shared cached data.
	6.	Cache additional data for potential future use:
	•	Best crossing time & weather data (1st choice).
	•	Second best crossing time & weather data.

# Key Constraints and Considerations
	•	Avoid creating a shared framework.
	•	Do not modify or delete the @Shared folder, as it is already used in multiple parts of the app. We should use it.
	•	Follow coding guidelines from @swiftrules.md as we evolve the implementation.
	•	Use the existing app group: group.genco
	•	Ensure target bundle IDs follow this pattern: generouscorp.ggb.
	•	Explicitly reference targets with correct naming conventions to avoid confusion:
	•	GGB Weather (main iOS app).
	•	GGBWidgetExtension (iOS widget).
	•	GGB Watch App (watchOS app).
	•	GGB Watch Widget Extension (watchOS widget).

# Guidance Approach

Before making any changes:
	1.	Develop a step-by-step plan and store it in @plan.md.
	•	This document will outline:
	•	Each step of the implementation in a structured way.
	•	Which files and targets need modification.
	•	Clear, explicit instructions on what to change and why.
	2.	Ensure testing accounts for first-time widget installation behavior.
	•	When installing the widget for the first time, it should immediately pull cached data from the iPhone so we don’t have to wait for the next data refresh.
	•	If this behavior is not working, we need to investigate how WidgetKit initializes and updates its timeline.
	3.	Execute the plan step-by-step, updating @plan.md with progress tracking.
	•	This ensures:
	•	Clarity before making changes.
	•	Accountability for progress tracking.
	•	A structured approach to avoid unnecessary modifications.