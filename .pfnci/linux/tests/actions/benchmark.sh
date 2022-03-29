#!/bin/bash

set -uex

git clone https://github.com/cupy/cupy-performance.git performance
# TODO(ecastill): make this optional
pip install seaborn
ls
pushd performance
python prof.py benchmarks/bench_ufunc_cupy.py -c

mkdir target
mv *.csv target/

# Run benchmarks for master branch
# Since GCP instance may change and use diff gen processsors/GPUs
# we just recompile and run to avoid false errors
pip uninstall -y cupy
if [[ "${PULL_REQUEST:-}" == "" ]]; then
    # For branches we compare against the latest release
    # TODO(ecastill) find a programatical way of doing this
    # sorting tags, or just checking the dates may mix the
    # stable & master branches
    git checkout tags/v11.0.0a2 -b v11.0.0a2
else
    git checkout master
fi

pip install --user -v .
python prof.py benchmarks/bench_ufunc_cupy.py -c
mkdir baseline
mv *.csv baseline/

# Compare with current branch
for bench in *.csv
do
    python regresion_detect.py master/${bench} pr/${bench}
done

popd
