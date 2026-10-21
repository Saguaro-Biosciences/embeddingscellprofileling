#!/usr/bin/env python3
"""Build a CellProfiler LoadData CSV for one Yokogawa CQ1 plate/timepoint Image folder.

CQ1 files are named W<well>F<field>T<time>Z<z>C<channel>.tif, e.g. W0026F0001T0001Z001C5.tif.
The well index runs row-major over the plate columns (384-well: W0001 = A01, W0026 = B02).

The output has one row per field, with FileName_<name>/PathName_<name> for every mapped channel,
then Metadata_Timepoint, Metadata_Site, Metadata_Well and Metadata_Plate, which is the layout
CELLPROFILER_ILLUM, QC_MULT and the embedding extractors read.

The script refuses to write a file it cannot trust:
  * unfinished transfers (*.partial files) in the folder,
  * fields missing one of the mapped channels,
  * more than one timepoint or z-plane in the folder,
  * image files the pipeline cannot read (e.g. mode 000 after a bad NAS copy).

Example:
  make_load_data.py --image-dir /mnt/ugreen_nas_v3/iric/RUN/20261014T154315_YKG-CQ1/Image \
      --path-prefix /mnt/s3/RUN/20261014T154315_YKG-CQ1/Image \
      --channel-map "Mito=C1 Alexa=C2 Cyto=C3 ER=C4 DNA=C5" --plate YKG --time 0 \
      --output s3://cellprofiler-resuts/IRIC/RUN/load_data_YKG_0.csv
"""
import argparse
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

import pandas as pd

CQ1_NAME = re.compile(r'^W(\d+)F(\d+)T(\d+)Z(\d+)C(\d+)\.tif{1,2}$', re.IGNORECASE)
PLATE_XML = re.compile(r'_(\d+)x(\d+)\.xml$', re.IGNORECASE)


def parse_channel_map(text):
    """'Mito=C1 Alexa=C2' or 'Mito:1,Alexa:2' -> {'Mito': 1, 'Alexa': 2}, order kept."""
    out = {}
    for tok in re.split(r'[\s,]+', text.strip()):
        if not tok:
            continue
        m = re.fullmatch(r'([A-Za-z][A-Za-z0-9_]*)[=:]C?(\d+)', tok, re.IGNORECASE)
        if not m:
            sys.exit(f"ERROR: cannot parse channel map entry '{tok}'. Use NAME=C<n>, e.g. 'DNA=C5'.")
        name, idx = m.group(1), int(m.group(2))
        if name in out:
            sys.exit(f"ERROR: channel name '{name}' appears twice in the channel map.")
        out[name] = idx
    if len(set(out.values())) != len(out):
        sys.exit('ERROR: two channel names point at the same CQ1 channel number.')
    if not out:
        sys.exit('ERROR: empty channel map.')
    return out


def plate_columns(image_dir, override):
    """Columns of the plate: --plate-columns, else the CQ1 plate file MP_*_<cols>x<rows>.xml next to Image/."""
    if override:
        return override
    for f in sorted(Path(image_dir).parent.glob('*.xml')):
        m = PLATE_XML.search(f.name)
        if m:
            return int(m.group(1))
    sys.exit('ERROR: no MP_*_<cols>x<rows>.xml plate file next to the Image folder; pass --plate-columns.')


def well_name(index, ncols):
    row, col = divmod(index - 1, ncols)
    return f'{chr(ord("A") + row)}{col + 1:02d}'


def exists(path):
    if path.startswith('s3://'):
        import fsspec
        return fsspec.filesystem('s3').exists(path)
    return Path(path).exists()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--image-dir', required=True, help='Folder holding the CQ1 TIFFs, as seen by this process')
    ap.add_argument('--path-prefix', required=True, help='Folder written into PathName_* (as CellProfiler sees it, e.g. /mnt/s3/...)')
    ap.add_argument('--channel-map', default=None, help="Channel names to CQ1 channel numbers, e.g. 'Mito=C1 Alexa=C2 Cyto=C3 ER=C4 DNA=C5'")
    ap.add_argument('--plate', required=True)
    ap.add_argument('--time', required=True)
    ap.add_argument('--plate-columns', type=int, default=None, help='Override plate columns (default: read from MP_*_<cols>x<rows>.xml)')
    ap.add_argument('--require-channels', nargs='*', default=[], help='Channel names downstream steps use; each must be in the map')
    ap.add_argument('--output', required=True, help='Destination CSV, local path or s3:// URI')
    ap.add_argument('--local-copy', default=None, help='Also write the CSV here (for Nextflow to publish)')
    ap.add_argument('--overwrite', action='store_true', help='Replace an existing load_data file')
    ap.add_argument('--skip-readability-check', action='store_true', help='Do not open-test every image file')
    a = ap.parse_args()

    if exists(a.output) and not a.overwrite:
        print(f'load_data already exists, leaving it unchanged: {a.output}')
        return

    if not a.channel_map:
        sys.exit(f'ERROR: no load_data at {a.output} and no channel map to build one. '
                 "Pass --channel_map, e.g. 'Mito=C1 Alexa=C2 Cyto=C3 ER=C4 DNA=C5'.")
    cmap = parse_channel_map(a.channel_map)
    missing = [c for c in a.require_channels if c not in cmap]
    if missing:
        sys.exit(f'ERROR: channels {missing} are used downstream but not in --channel-map {list(cmap)}.')

    image_dir = Path(a.image_dir)
    if not image_dir.is_dir():
        sys.exit(f'ERROR: image folder not found: {image_dir}')
    names = os.listdir(image_dir)
    partial = [n for n in names if n.endswith('.partial')]
    if partial:
        sys.exit(f'ERROR: {len(partial)} unfinished transfer files (*.partial) in {image_dir}, e.g. {partial[0]}. '
                 'Wait for the copy to finish.')

    files = defaultdict(dict)          # (well, field) -> {channel_number: filename}
    times, zs, other = set(), set(), 0
    for n in names:
        m = CQ1_NAME.match(n)
        if not m:
            other += 1
            continue
        w, f, t, z, c = map(int, m.groups())
        times.add(t); zs.add(z)
        files[(w, f)][c] = n
    if not files:
        sys.exit(f'ERROR: no CQ1 images (W####F####T####Z###C#.tif) in {image_dir}')
    if len(times) > 1 or len(zs) > 1:
        sys.exit(f'ERROR: folder holds {len(times)} timepoints and {len(zs)} z-planes; one of each is supported.')

    wanted = set(cmap.values())
    incomplete = {k: sorted(wanted - set(v)) for k, v in files.items() if not wanted <= set(v)}
    if incomplete:
        ex = list(incomplete.items())[:5]
        sys.exit(f'ERROR: {len(incomplete)} fields lack mapped channels, e.g. ' +
                 ', '.join(f'W{w:04d}F{f:04d} missing C{miss}' for (w, f), miss in ex))
    unused = sorted({c for v in files.values() for c in v} - wanted)

    ncols = plate_columns(image_dir, a.plate_columns)
    prefix = a.path_prefix.rstrip('/') + '/'
    rows = []
    for (w, f) in sorted(files):
        r = {}
        for name, c in cmap.items():
            r[f'FileName_{name}'] = files[(w, f)][c]
            r[f'PathName_{name}'] = prefix
        r.update(Metadata_Timepoint=a.time, Metadata_Site=f, Metadata_Well=well_name(w, ncols), Metadata_Plate=a.plate)
        rows.append(r)
    df = pd.DataFrame(rows)

    if not a.skip_readability_check:
        # Open every file for real: os.access() can say yes for root while the NFS server still refuses the read
        from concurrent.futures import ThreadPoolExecutor

        def readable(n):
            try:
                with open(image_dir / n, 'rb') as fh:
                    fh.read(1)
                return True
            except OSError:
                return False

        names_used = list(df[[f'FileName_{c}' for c in cmap]].to_numpy().ravel())
        with ThreadPoolExecutor(16) as pool:
            unreadable = [n for n, ok in zip(names_used, pool.map(readable, names_used)) if not ok]
        if unreadable:
            sys.exit(f'ERROR: {len(unreadable)} of {df.shape[0] * len(cmap)} images are not readable, '
                     f'e.g. {unreadable[0]}. On the UGREEN NAS this is the mode-000 copy problem; '
                     f'fix with: chmod -R a+rX "{image_dir.parent}"')

    if a.local_copy:
        df.to_csv(a.local_copy, index=False)
    df.to_csv(a.output, index=False)
    wells = df.Metadata_Well.nunique()
    print(f'Wrote {a.output}: {len(df)} fields, {wells} wells ({df.Metadata_Well.iloc[0]}..{df.Metadata_Well.iloc[-1]}), '
          f'channels {", ".join(f"{k}=C{v}" for k, v in cmap.items())}' +
          (f'; ignored channels {["C%d" % c for c in unused]}' if unused else '') +
          (f'; ignored {other} non-image files' if other else ''))


if __name__ == '__main__':
    main()
