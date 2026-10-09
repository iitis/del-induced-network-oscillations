"""Check source/documentation wiring without MATLAB or scientific input files.

Run from the root: python3 tests/check_repository_static.py
MATLAB semantics and execution are deliberately deferred to TASK.
"""
from pathlib import Path
import ast
import re
import shutil
import subprocess


def main():
    root = Path(__file__).resolve().parents[1]
    sources = [*root.glob('*.m'), *root.glob('*.sh'),
               *root.glob('configs/*.m'), *root.glob('tests/*.m'), *root.glob('tests/*.py')]
    for path in sources:
        text = path.read_text(encoding='utf-8')
        assert b'\r' not in path.read_bytes(), f'{path.name}: non-LF text'
        if path.suffix == '.py':
            ast.parse(text, filename=str(path))
        if path.suffix == '.m':
            declaration = next(line for line in text.splitlines() if line.startswith('function '))
            match = re.search(r'(?:=\s*|^function\s+)(\w+)\s*\(', declaration)
            assert match and match.group(1) == path.stem, f'{path.name}: function/file name mismatch'
    title = 'Delay-induced network oscillations shape epileptic fast ripple activity in a computational model based on human epileptic tissue data'
    for name in ['README.md', 'README_REPRODUCIBILITY.md', 'RUNNING_BATCH_EXPERIMENTS.md', 'data/README.md']:
        text = (root/name).read_text(encoding='utf-8')
        assert text.count('```') % 2 == 0, f'{name}: unterminated code block'
        assert 'Statistical Mechanics of Spike Trains' not in text, name
        if name in ['README.md','README_REPRODUCIBILITY.md']:
            assert title in text, name
        for script in re.findall(r'\b(?:sbatch\s+)(\w+\.sh)', text):
            assert (root/script).is_file(), f'{name}: missing {script}'
    for name in ['restore_simulation_rng','validate_network_state','motif_index',
                 'runSim4quart','run_batch_runSim4quart','run_experiment_batch_cli']:
        assert (root/f'{name}.m').is_file(), name
    rng = (root/'restore_simulation_rng.m').read_text(encoding='utf-8')
    assert "'shuffle'" not in rng and 'stream.State =' in rng
    sim = (root/'runSim4quart.m').read_text(encoding='utf-8')
    assert "'shuffle'" not in sim and 'init_rasters;' not in sim and 'plot_rasters;' not in sim
    assert 'G.rand_ext_cursor = rand_ext_col' in sim and 'G.rng_state = defaultStream.State' in sim
    assert 'onCleanup' in sim and 'completed_requested_duration' in sim
    batch = (root/'run_batch_runSim4quart.m').read_text(encoding='utf-8')
    assert 'mean(G.A);' not in batch and 'mean(G.s_mean);' not in batch
    assert batch.index('validate_network_state(baseG') < batch.index('G.rand_ext = rand(')
    assert 'run_metadata' in batch and "'error'" in batch
    for path in root.glob('submit_*.sh'):
        text = path.read_text(encoding='utf-8')
        assert 'set -euo pipefail' in text and 'SLURM_SUBMIT_DIR' in text, path.name
    main_wrapper = (root/'submit_runSim4quart.sh').read_text(encoding='utf-8')
    assert "getenv('SIM_INPUT_FILE')" in main_wrapper and "getenv('SIM_CONFIG_FUNCTION')" in main_wrapper
    alias = (root/'submit_runSim4quart_batch.sh').read_text(encoding='utf-8')
    assert 'exec bash' in alias and '/submit_runSim4quart.sh' in alias
    validation = (root/'submit_validation.sh').read_text(encoding='utf-8')
    assert 'run_task_validation' in validation and 'sha256sum' in validation
    for name in ['config_publication_example','config_grid_lr_esr']:
        assert 'config.plot = false' in (root/f'configs/{name}.m').read_text(encoding='utf-8')
    # External MAT files may exist locally; ensure they are not tracked.
    git = ['git','-c',f'core.worktree={root.as_posix()}']
    tracked = subprocess.check_output(git+['ls-files'], cwd=root, universal_newlines=True).splitlines()
    assert not any(name.lower().endswith('.mat') for name in tracked), 'Scientific/generated MAT is tracked'
    subprocess.run(git+['diff','--check'], cwd=root, check=True)
    for sample in ['data/example.mat','validation_results/example.mat']:
        subprocess.run(git+['check-ignore','-q',sample], cwd=root, check=True)
    bash = shutil.which('bash')
    if bash:
        for path in root.glob('submit_*.sh'):
            subprocess.run([bash,'-n',str(path)], check=True)
        print('PASS: shell syntax (bash -n)')
    else:
        print('SKIP: shell syntax (Bash unavailable; check on TASK)')
    print('PASS: UTF-8/LF, Python syntax, MATLAB function names, documentation/title/code fences, wrappers, RNG/summary/replay wiring, external-data ignore rules, git diff --check')
    print('PENDING: MATLAB parsing, unit tests, external-state smoke test')


if __name__ == '__main__':
    main()
