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


function FindAndCheckMSVC {
    # Note: this assumes vs2017, e.g. see _find_vc2017():
    # https://github.com/pypa/setuptools/blob/9692cde009af4651819d18a1e839d3b6e3fcd77d/setuptools/_distutils/_msvccompiler.py#L67

    $vsPath = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" `
              -latest `
              -products * `
              -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
              -property installationPath
    $clPath = Join-Path $vsPath "VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe"
    $clPath = Get-ChildItem $clPath

    $CL_VERSION_STRING = & $clPath /?
    if ($CL_VERSION_STRING -match "Version (\d+\.\d+)\.\d+") {
        $CL_VERSION = [version]$matches[1]
        echo "Detected cl.exe version: $CL_VERSION"
    }
}


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

        # Check MSVC version
        # TODO: we might want to be able to choose MSVC version in the future
        FindAndCheckMSVC

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
