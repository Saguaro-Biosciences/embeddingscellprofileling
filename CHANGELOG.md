# Saguaro-Biosciences/lembeddingscellprofileling: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0dev - [date]

Initial release of Saguaro-Biosciences/lembeddingscellprofileling, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- `LOAD_DATA` module (`bin/make_load_data.py`): builds the CellProfiler load_data CSV for each samplesheet row from its CQ1 Image folder before `CELLPROFILER_ILLUM` runs. New parameters `--make_load_data`, `--channel_map`, `--overwrite_load_data` and `--plate_columns`. Existing load_data files are kept unless `--overwrite_load_data`.

### `Fixed`

### `Dependencies`

### `Deprecated`
