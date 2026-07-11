# Requirements: Debug Seamstress Sequencer

## Questions & Answers

### Q1: Which seamstress version should we target?

**A:** seamstress v1.4.7. The v2.0.0-alpha has breaking API changes (grid, metro, etc.) that don't match our code. v1 has the same API surface as norns — grid.connect(), metro.init(), params, clock — and all our modules load and run correctly on it. Installed via `brew install ryleelyman/seamstress/seamstress@1`.

