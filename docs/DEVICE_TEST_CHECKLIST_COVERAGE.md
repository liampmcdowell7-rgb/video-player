# Device test checklist: attribution, Online Lookup text, artwork sizes (COVERAGE agent, batch 3)

Nothing here has been seen on an Apple TV. Each line is a check for the first device run.

| # | Check | Expected |
|---|---|---|
| CV1 | Discover (Search tab, empty field) with a TMDB key, scroll to the end | The two notices show as plain secondary caption text under the shelves: the "uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB" sentence and "Where-to-watch data is provided by JustWatch." No logo |
| CV2 | Settings > Online Lookup | Footer under the status reads the full "Nothing is sent ..." text; one key row, "TMDB" (#27: no OMDb row); a "Data Sources" section at the bottom shows the same two notices |
| CV3 | Settings > About > Data Sources | The about note and the same two notices; no ratings sentence |
| CV4 | Settings > Online Lookup with no key and Free Data Sources off | Status: "Online lookup is off. No key is entered." Nothing is sent (watch with a network log on the router if possible). #27: replaces the OMDb-only case (OMDb removed) |
| CV5 | Long texts on the Online Lookup footer with Larger Text on | The footer wraps, nothing is cut |
| CV6 | A movie grid with online posters on a 4K TV, focus a poster | The poster is sharp when focused (requested at w780). Compare with a w500 build if one exists |
| CV7 | A 4K PNG poster over 8 MB next to a video | It is used (not the online poster); memory stays normal while scrolling a grid of such posters |
| CV8 | Fix Match and Discover with no key | Texts say "your own TMDB key" and point to Settings > Online Lookup |
