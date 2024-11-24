Param(
    [Parameter(Mandatory=$true)]
    [String]$stage,
    [Parameter(Mandatory=$false)]
    [String]$python,
    [Parameter(Mandatory=$false)]
    [String]$cuda
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_error_handler.ps1"

. "$PSScriptRoot\_flexci.ps1"


function Main {
    # Setup environment
    if ($stage -eq "setup") {
        echo "Using CUDA $cuda and Python $python"
        ActivateCUDA $cuda
        if ($cuda -eq "10.2") {
            ActivateCuDNN "8.6" $cuda
        } else {
            ActivateCuDNN "8.8" $cuda
        }
        ActivateNVTX1
        ActivatePython $python
        echo "Setting up test environment"
        RunOrDie python -V
        RunOrDie python -m pip install -U pip setuptools wheel
        RunOrDie python -m pip freeze

        return
    }
    elseif ($stage -eq "build") {
        # Setup build environment variables
        $Env:CUPY_NUM_BUILD_JOBS = "16"
        $Env:CUPY_NVCC_GENERATE_CODE = "current"
        echo "Environment:"
        RunOrDie cmd.exe /C set

        echo "Building..."
        $build_retval = 0
        RunOrDie python -m pip install -U "numpy" "scipy==1.12.*"
        python -m pip install ".[all,test]" -v
        if (-not $?) {
            $build_retval = $LastExitCode
        }

        if ($build_retval -ne 0) {
            throw "Build failed with status $build_retval"
        }

        return
    }
    elseif ($stage -eq "test") {
        $pytest_opts = "-m", '"not slow"'
    }
    elseif ($stage -eq "slow") {
        $pytest_opts = "-m", "slow"
    }
    else {
        throw "Unsupported stage: $stage"
    }

    $Env:CUPY_TEST_GPU_LIMIT = $Env:GPU
    $Env:CUPY_DUMP_CUDA_SOURCE_ON_ERROR = "1"

    # # TODO: update this function?
    # $is_pull_request = IsPullRequestTest
    # if (-Not $is_pull_request) {
    #     $Env:CUPY_TEST_FULL_COMBINATION = "1"
    # }

    # # TODO: do we still need zlib these days?
    # # Install dependency for cuDNN 8.3+
    # echo ">> Installing zlib"
    # InstallZLIB

    pushd tests
    echo "CuPy Configuration:"
    RunOrDie python -c "import cupy; print(cupy); cupy.show_config()"
    echo "Running test..."
    $pytest_tests = "cupy_tests/core_tests/test*.py"  # TODO: remove me
    # TODO: pass timeout as a function argument?
    $test_retval = RunWithTimeout -timeout 18000 -- python -m pytest -rfEX @pytest_opts @pytest_tests
    popd

    if ($test_retval -ne 0) {
        throw "Test failed with status $test_retval"
    }
}

Main
