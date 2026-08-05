# PricingEntry

How generic drug prices change with the number of firms.

## Structure

This repository follows the Gentzkow lab template. Each module has a
`source/` directory with code, a `make.sh` that runs it, and a
`get_inputs.sh` that links its inputs into `input/`. Outputs go to
`output/` (committed) or `output_local/` (ignored by Git).

- `1_data/` — data cleaning
  - `1_clean_prices/` — clean raw price and firm-count data
- `2_analysis/` — data analysis
  - `1_analyze_price_entry/` — relate generic prices to the number of firms
- `external/Dropbox` — link to `C:\Users\scz7085\Dropbox\PricingEntry\Data`
- `lib/` — shared shell runners and setup scripts

## Setup

1. Edit `local_env.sh` (created from `lib/setup/local_env_template.sh`)
   to point to your local executables and external data paths.
2. Run `setup.sh` to create external links and module input links.
3. Run `run_all.sh` to build all modules, or a module's `make.sh` to
   build it alone.
