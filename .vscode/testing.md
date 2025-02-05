# Testing Instructions for watchOS Widget

## Prerequisites
1. Xcode 15+ with watchOS simulator
2. iOS simulator or device
3. Internet connection for initial setup

## Test Cases

### 1. Initial Setup & Installation
1. Build and run iOS app
2. Add widget to watch face
3. Expected: Widget should immediately show weather data from cache
4. Verify: Temperature, wind speed, and precipitation probability display correctly

### 2. Cache Updates
1. Wait 15 minutes for background refresh
2. Check widget updates with new data
3. Verify: Data timestamp is recent
4. Expected: Smooth transition between updates

### 3. Offline Functionality
1. Enable Airplane mode on iOS device
2. Wait for next refresh cycle
3. Expected: Widget continues showing cached data
4. Verify: Cache staleness error after 15 minutes

### 4. Error States
1. Test no cache available:
   - Clear app data
   - Install widget
   - Expected: Shows "No weather data available"
2. Test stale cache:
   - Disable network
   - Wait 15+ minutes
   - Expected: Shows "Weather data is outdated"

### 5. Background Refresh
1. Background iOS app for 15 minutes
2. Return to foreground
3. Expected: New weather data available
4. Verify: Cache timestamp updated

## Validation Checklist
- [ ] Widget shows correct initial data
- [ ] Background updates work every 15 minutes
- [ ] Offline mode shows cached data
- [ ] Error states display correctly
- [ ] Data sharing between iOS and watchOS works
- [ ] Widget timeline updates properly

## Known Limitations
- First-time installation requires internet connectivity
- Cache updates limited to 15-minute intervals
- Background refresh may be delayed by system

## Troubleshooting
1. If widget shows no data:
   - Check app group entitlements
   - Verify iOS app has run once
   - Check network connectivity
2. If updates are delayed:
   - Verify background refresh is enabled
   - Check system background app refresh settings 