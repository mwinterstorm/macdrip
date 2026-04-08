# MacDrip Roadmap

## Path to v2:
1. [x] UI & Persistence. Uncouple the current code from the MenuBarExtra, spawn a main macOS Window, and implement SwiftData so that the history you currently fetch is actually saved to disk.
2. [ ] Expanded Data. Update your fetch routines to also grab carbs and insulin data from the phone.
3. [x] Charting. Rebuild the main dashboard chart to span 24 hours.

## v2.1 — Chart & Dashboard Enhancements
4. [ ] **Hover Tooltips on Chart Data Points.** Show a popover on the dashboard chart when hovering over a data point, displaying time, mmol/L value, and trend arrow.
5. [ ] **Dynamic Y-Axis Scaling.** Both dashboard and mini menu-bar charts use a dynamic Y-axis: min = min(3, floor(lowest displayed value)), max = max(12, ceil(highest displayed value) rounded up to nearest even number).
6. [ ] **Smarter Polling Rate.** When data is stale (>7 min since last reading), poll slower (e.g. 60 seconds), and when goes over 10 mins poll slower still (e.g. 2 minutes), and when goes over 15 mins poll slower still (e.g. 5 minutes), and when goes over 30 mins poll slower still (e.g. 10 minutes), and when goes over 60 mins poll slower still (e.g. 30 minutes), and when goes over 120 mins poll slower still (e.g. 60 minutes).
7. [ ] **Time in Range (TIR) Statistics.** Add a summary section to the History view (or a new Statistics tab) showing percentage of time spent in target range (3.9–10.0 mmol/L) over the last 24 hours.
8. [ ] **Customizable Chart Time Scales.** Add a picker to switch between 3, 6, 12, and 24-hour chart views on the dashboard.