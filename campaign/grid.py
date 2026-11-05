"""TASK grid inventory, immutable manifest, input verification and progress (Python 3.6+)."""
import argparse
import hashlib
import json
import re
from decimal import Decimal
from itertools import product
from pathlib import Path

PROJECT = Path('/users/project1/pt01269')
INPUT = PROJECT / 'in_delmean=16q_pii=0.05_zoom'


def inside(path, root):
    path = path.resolve()
    path.relative_to(root.resolve())
    return path


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(2**20), b''):
            digest.update(block)
    return digest.hexdigest()


def make_manifest(directory, pattern, project=PROJECT):
    rows = {}
    for file in sorted(directory.glob('*.mat')):
        match = re.fullmatch(pattern, file.name)
        if not match:
            raise ValueError('Filename does not match coordinate pattern: ' + file.name)
        xy = tuple(Decimal(match.group(axis)) for axis in ('x', 'y'))
        if not all(value.is_finite() for value in xy) or xy in rows:
            raise ValueError('Invalid or duplicate coordinates: ' + file.name)
        rows[xy] = inside(file, project)
    xs, ys = (sorted({key[i] for key in rows}) for i in (0, 1))
    if len(xs) != 9 or len(ys) != 9 or set(rows) != set(product(xs, ys)):
        raise ValueError('Expected complete 9x9 grid; found {} files, {} x values, {} y values'.format(
            len(rows), len(xs), len(ys)))
    return [{'id': i, 'x': str(x), 'y': str(y), 'input': str(rows[x, y]),
             'sha256': sha256(rows[x, y])}
            for i, (x, y) in enumerate(product(xs, ys), 1)]


def progress(run, row):
    point = run / 'points' / '{:03d}'.format(row['id'])
    completed = 0
    hours = sorted(point.glob('hour_[0-9][0-9]'))
    for hour in hours:
        if hour.name != 'hour_{:02d}'.format(completed + 1):
            raise ValueError('Gap in committed hours: ' + str(point))
        info = json.loads((hour / 'metadata.json').read_text(encoding='utf-8'))
        if (info['input_sha256'] != row['sha256'] or
                info['hour'] != completed + 1 or
                any(not (hour / (name + '.mat')).is_file() or
                    (hour / (name + '.mat')).stat().st_size != info[name + '_bytes']
                    for name in ('checkpoint', 'recordings'))):
            raise ValueError('Invalid committed hour: ' + str(hour))
        if info['seconds_completed'] == 3600:
            completed += 1
        if info['stop_reason'] != 'completed':
            if hour != hours[-1]:
                raise ValueError('Output exists after terminal stop: ' + str(point))
            return completed, info['stop_reason']
        if info['seconds_completed'] != 3600:
            raise ValueError('Incomplete hour marked completed: ' + str(hour))
    return completed, 'complete' if completed == 12 else 'pending'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['inventory', 'manifest', 'verify', 'status'])
    parser.add_argument('--input', type=Path, default=INPUT)
    parser.add_argument('--run', type=Path)
    parser.add_argument('--pattern', help='Full filename regex with named groups x and y')
    parser.add_argument('--id', type=int)
    args = parser.parse_args()
    directory = inside(args.input, PROJECT)
    if args.action == 'inventory':
        for path in sorted(directory.glob('*.mat')):
            print('{}\t{}'.format(path.name, path.stat().st_size))
        return
    if args.run is None:
        parser.error('--run is required')
    run = inside(args.run, PROJECT / 'runs')
    manifest = run / 'manifest.json'
    if args.action == 'manifest':
        if not args.pattern:
            parser.error('--pattern is required; inspect inventory first')
        rows = make_manifest(directory, args.pattern)
        run.mkdir(parents=True, exist_ok=True)
        (run / 'logs').mkdir(exist_ok=True)
        with manifest.open('x', encoding='utf-8') as handle:
            json.dump(rows, handle, indent=2)
            handle.write('\n')
        return
    rows = json.loads(manifest.read_text(encoding='utf-8'))
    if [row['id'] for row in rows] != list(range(1, 82)):
        raise ValueError('Invalid manifest IDs')
    if args.action == 'verify':
        if args.id not in range(1, 82):
            parser.error('--id must be 1..81')
        row = rows[args.id - 1]
        if sha256(inside(Path(row['input']), PROJECT)) != row['sha256']:
            raise ValueError('Input checksum mismatch for point {}'.format(args.id))
    else:
        for row in rows:
            count, state = progress(run, row)
            print('{:03d}\t{}\t{}\t{}/12\t{}'.format(
                row['id'], row['x'], row['y'], count, state))


if __name__ == '__main__':
    main()
