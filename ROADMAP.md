# MacDrip Roadmap

## Path to v2:
1. [x] UI & Persistence. Uncouple the current code from the MenuBarExtra, spawn a main macOS Window, and implement SwiftData so that the history you currently fetch is actually saved to disk.
2. [ ] Expanded Data. Update your fetch routines to also grab carbs and insulin data from the phone.
3. [x] Charting. Rebuild the main dashboard chart to span 24 hours.

## v2.0 — Chart & Dashboard Enhancements
4. [x] **Hover Tooltips on Chart Data Points.** Show a popover on the dashboard chart when hovering over a data point, displaying time, mmol/L value, and trend arrow.
5. [x] **Dynamic Y-Axis Scaling.** Both dashboard and mini menu-bar charts use a dynamic Y-axis: min = min(3, floor(lowest displayed value)), max = max(12, ceil(highest displayed value) rounded up to nearest even number).
6. [x] **Smarter Polling Rate.** When data is stale (>7 min since last reading), poll slower (e.g. 60 seconds), and when goes over 10 mins poll slower still (e.g. 2 minutes), and when goes over 15 mins poll slower still (e.g. 5 minutes), and when goes over 30 mins poll slower still (e.g. 10 minutes), and when goes over 60 mins poll slower still (e.g. 30 minutes), and when goes over 120 mins poll slower still (e.g. 60 minutes).
7. [x] **Time in Range (TIR) Statistics.** Add a summary section to the History view showing percentage of time spent in target range (configurable, default 3.9–10.0 mmol/L) over the last 24 hours.
8. [x] **Customizable Chart Time Scales.** Add a picker to switch between 3, 6, 12, and 24-hour chart views on the dashboard.

## v2.1 — Advanced Analytics & Visualizations
9. [ ] **Ambulatory Glucose Profile (AGP / Modal Day).** Overlay multiple days of data (e.g. 14 days) onto a single 24-hour axis. Show a bold median line for the "typical" glucose at any time of day, with shaded percentile bands (25th–75th and 10th–90th) to visualise variability. Useful for identifying consistent patterns like Dawn Phenomenon or recurring post-meal spikes.
10. [ ] **Glucose Variability Heatmap.** A grid where X-axis = day of the week and Y-axis = hour of the day. Each cell is coloured by average glucose for that hour (blue for lows, red for highs). Allows spotting "trouble spots" at a glance — e.g. weekend vs weekday differences.
11. [ ] **Poincaré (Delay) Plot.** Plot each glucose value (Gᵢ) against the previous value (Gᵢ₋₁). Stable glucose forms a tight diagonal line; high volatility scatters into a wide ellipse. Provides a mathematical view of short-term variability and fluctuation speed.
12. [ ] **Glucose Coefficient of Variation (CV%).** A variability gauge showing CV% = (Standard Deviation / Mean Glucose) × 100. Clinical target is ≤36%. A higher value indicates "swingy" glucose even if the average (HbA1c equivalent) looks good. Display as a gauge or bar chart over configurable time periods.
13. [ ] **Day-to-Day Overlay.** Plot the last 3–7 days as individual, semi-transparent lines on a single 24-hour graph (unlike AGP which merges into percentiles). Shows whether a spike was a one-off or a daily pattern. Use `LineMark` with `foregroundStyle(by: .value("Day", dayString))` for automatic colour-coding.