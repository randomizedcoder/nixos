{ config
, stdenv
, lib
, fetchFromGitHub
, abseil-cpp_202407
, cmake
, cpuinfo
, eigen
, flatbuffers_23
, glibcLocales
, gtest
, howard-hinnant-date
, libpng
, nlohmann_json
, pkg-config
, python3Packages
, re2
, zlib
, protobuf
, microsoft-gsl
, darwinMinVersionHook
, pythonSupport ? true
, cudaSupport ? config.cudaSupport
, ncclSupport ? config.cudaSupport
, cudaPackages ? { }
, rocmSupport ? false
, rcclSupport ? rocmSupport
, rocmPackages ? { }
,
}@inputs:

let
  version = "1.22.2";

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "onnxruntime";
    tag = "v${version}";
    fetchSubmodules = true;
    hash = "sha256-X8Pdtc0eR0iU+Xi2A1HrNo1xqCnoaxNjj4QFm/E3kSE=";
  };

  stdenv = throw "Use effectiveStdenv instead";
  effectiveStdenv = if cudaSupport then cudaPackages.backendStdenv else inputs.stdenv;

  cudaArchitecturesString = cudaPackages.flags.cmakeCudaArchitecturesString;

  mp11 = fetchFromGitHub {
    owner = "boostorg";
    repo = "mp11";
    tag = "boost-1.89.0";
    hash = "sha256-HcQJ/PXBQdWVjGZy28X2LxVRfjV2nkeLTusNjT9ssXI=";
  };

  safeint = fetchFromGitHub {
    owner = "dcleblanc";
    repo = "safeint";
    tag = "3.0.28a";
    hash = "sha256-MT2nba15DDApNQZxOBkf0DPvc759rEhpwfcD6ERphl0=";
  };

  onnx = fetchFromGitHub {
    owner = "onnx";
    repo = "onnx";
    tag = "v1.17.0";
    hash = "sha256-9oORW0YlQ6SphqfbjcYb0dTlHc+1gzy9quH/Lj6By8Q=";
  };

  cutlass = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "cutlass";
    tag = "v3.5.1";
    hash = "sha256-sTGYN+bjtEqQ7Ootr/wvx3P9f8MCDSSj3qyCWjfdLEA=";
  };

  dlpack = fetchFromGitHub {
    owner = "dmlc";
    repo = "dlpack";
    tag = "v1.1";
    hash = "sha256-RoJxvlrt1QcGvB8m/kycziTbO367diOpsnro49hDl24=";
  };

  isCudaJetson = cudaSupport && cudaPackages.flags.isJetsonBuild;
in
effectiveStdenv.mkDerivation rec {
  pname = "onnxruntime";
  inherit src version;

  patches = lib.optionals cudaSupport [
    # We apply the referenced 1064.patch ourselves to our nix dependency.
    #  FIND_PACKAGE_ARGS for CUDA was added in https://github.com/microsoft/onnxruntime/commit/87744e5 so it might be possible to delete this patch after upgrading to 1.17.0
    ./nvcc-gsl.patch
  ];

  nativeBuildInputs = [
    cmake
    pkg-config
    python3Packages.python
    protobuf
  ]
  ++ lib.optionals pythonSupport (
    with python3Packages;
    [
      pip
      python
      pythonOutputDistHook
      setuptools
      wheel
    ]
  )
  ++ lib.optionals cudaSupport [
    cudaPackages.cuda_nvcc
    cudaPackages.cudnn-frontend
  ]
  ++ lib.optionals isCudaJetson [
    cudaPackages.autoAddCudaCompatRunpath
  ]
  ++ lib.optionals rocmSupport [
    rocmPackages.rocm-cmake
    rocmPackages.hipcc
    rocmPackages.llvm.clang
    rocmPackages.rocm-device-libs
  ];

  buildInputs = [
    eigen
    glibcLocales
    howard-hinnant-date
    libpng
    nlohmann_json
    microsoft-gsl
    zlib
  ]
  ++ lib.optionals (lib.meta.availableOn effectiveStdenv.hostPlatform cpuinfo) [
    cpuinfo
  ]
  ++ lib.optionals pythonSupport (
    with python3Packages;
    [
      numpy
      pybind11
      packaging
    ]
  )
  ++ lib.optionals cudaSupport (
    with cudaPackages;
    [
      cuda_cccl # cub/cub.cuh
      libcublas # cublas_v2.h
      libcurand # curand.h
      libcusparse # cusparse.h
      libcufft # cufft.h
      cudnn # cudnn.h
      cuda_cudart
    ]
    ++ lib.optionals (cudaSupport && ncclSupport) (
      with cudaPackages;
      [
        nccl
      ]
    )
  )
  ++ lib.optionals rocmSupport (
    with rocmPackages;
    [
      rocm-core
      rocm-runtime
      hipblas
      rocblas
      miopen
      rocfft
      rocsparse
    ]
    ++ lib.optionals (rocmSupport && rcclSupport) [
      rccl
    ]
  )
  ++ lib.optionals effectiveStdenv.hostPlatform.isDarwin [
    (darwinMinVersionHook "13.3")
  ];

  nativeCheckInputs = [
    gtest
  ]
  ++ lib.optionals pythonSupport (
    with python3Packages;
    [
      pytest
      sympy
      onnx
    ]
  );

  # TODO: build server, and move .so's to lib output
  # Python's wheel is stored in a separate dist output
  outputs = [
    "out"
    "dev"
  ]
  ++ lib.optionals pythonSupport [ "dist" ];

  enableParallelBuilding = true;

  cmakeDir = "../cmake";

  cmakeFlags = [
    (lib.cmakeBool "ABSL_ENABLE_INSTALL" true)
    (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
    (lib.cmakeBool "FETCHCONTENT_QUIET" false)
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_ABSEIL_CPP" "${abseil-cpp_202407.src}")
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_DLPACK" "${dlpack}")
           (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_FLATBUFFERS" "${flatbuffers_23.src}")
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_MP11" "${mp11}")
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_ONNX" "${onnx}")
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_RE2" "${re2.src}")
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_SAFEINT" "${safeint}")
    (lib.cmakeFeature "FETCHCONTENT_TRY_FIND_PACKAGE_MODE" "ALWAYS")
    # fails to find protoc on darwin, so specify it
    (lib.cmakeFeature "ONNX_CUSTOM_PROTOC_EXECUTABLE" (lib.getExe protobuf))
    (lib.cmakeBool "onnxruntime_BUILD_SHARED_LIB" true)
    (lib.cmakeBool "onnxruntime_BUILD_UNIT_TESTS" doCheck)
    (lib.cmakeBool "onnxruntime_USE_FULL_PROTOBUF" false)
    (lib.cmakeBool "onnxruntime_USE_CUDA" cudaSupport)
    (lib.cmakeBool "onnxruntime_USE_NCCL" (cudaSupport && ncclSupport))
    (lib.cmakeBool "onnxruntime_USE_ROCM" rocmSupport)
    (lib.cmakeBool "onnxruntime_USE_RCCL" (rocmSupport && rcclSupport))
    (lib.cmakeBool "onnxruntime_ENABLE_LTO" (!cudaSupport || cudaPackages.cudaOlder "12.8"))
  ]
  ++ lib.optionals pythonSupport [
    (lib.cmakeBool "onnxruntime_ENABLE_PYTHON" true)
  ]
  ++ lib.optionals cudaSupport [
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_CUTLASS" "${cutlass}")
    (lib.cmakeFeature "onnxruntime_CUDNN_HOME" "${cudaPackages.cudnn}")
    (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" cudaArchitecturesString)
    (lib.cmakeFeature "onnxruntime_NVCC_THREADS" "1")
  ]
  ++ lib.optionals rocmSupport [
    (lib.cmakeFeature "ROCM_PATH" "${rocmPackages.rocm-core}")
    # Comprehensive AMD GPU architecture support:
    # MI Cards: gfx900 (MI25/Vega 10), gfx906 (MI50/MI60/Vega 20), gfx908 (MI100/CDNA), gfx90a (MI200/CDNA2), gfx942 (MI300/CDNA3)
    # RDNA Cards: gfx1010 (RX 5700/Navi 10), gfx1011 (Pro 5600M/Navi 12), gfx1012 (RX 5500/Navi 14), gfx1020 (Navi 21 early), gfx1030 (RX 6800/6900/Navi 21/22), gfx1100 (RX 7900/Navi 31)
    (lib.cmakeFeature "CMAKE_HIP_ARCHITECTURES" "gfx900;gfx906;gfx908;gfx90a;gfx942;gfx1010;gfx1011;gfx1012;gfx1020;gfx1030;gfx1100")
    (lib.cmakeFeature "HIP_COMPILER" "${rocmPackages.hipcc}/bin/hipcc")
    (lib.cmakeFeature "CMAKE_CXX_COMPILER" "${rocmPackages.hipcc}/bin/hipcc")
  ];

  env = lib.optionalAttrs effectiveStdenv.cc.isClang {
    NIX_CFLAGS_COMPILE = "-Wno-error";
  } // lib.optionalAttrs rocmSupport {
    # ROCm environment variables for HIP compiler
    ROCM_PATH = "${rocmPackages.rocm-core}";
    HIP_PATH = "${rocmPackages.hipcc}";
    HIP_CLANG_PATH = "${rocmPackages.llvm.clang}/bin";
    HSA_PATH = "${rocmPackages.rocm-core}";
    HIP_PLATFORM = "amd";
    HIP_COMPILER = "clang";
    HIP_RUNTIME = "rocclr";
    # ROCm device library path
    ROCM_DEVICE_LIB_PATH = "${rocmPackages.rocm-device-libs}/lib";
  };

  doCheck =
    !(
      cudaSupport
      || builtins.elem effectiveStdenv.buildPlatform.system [
        # aarch64-linux fails cpuinfo test, because /sys/devices/system/cpu/ does not exist in the sandbox
        "aarch64-linux"
        # 1 - onnxruntime_test_all (Failed)
        # 4761 tests from 311 test suites ran, 57 failed.
        "loongarch64-linux"
      ]
    );

  requiredSystemFeatures = lib.optionals cudaSupport [ "big-parallel" ];

  hardeningEnable = lib.optionals (effectiveStdenv.hostPlatform.system == "loongarch64-linux") [
    "nostrictaliasing"
  ];

  postPatch = ''
    substituteInPlace cmake/libonnxruntime.pc.cmake.in \
      --replace-fail '$'{prefix}/@CMAKE_INSTALL_ @CMAKE_INSTALL_
    echo "find_package(cudnn_frontend REQUIRED)" > cmake/external/cudnn_frontend.cmake

    # https://github.com/microsoft/onnxruntime/blob/c4f3742bb456a33ee9c826ce4e6939f8b84ce5b0/onnxruntime/core/platform/env.h#L249
    substituteInPlace onnxruntime/core/platform/env.h --replace-fail \
      "GetRuntimePath() const { return PathString(); }" \
      "GetRuntimePath() const { return PathString(\"$out/lib/\"); }"
  ''
  + lib.optionalString (effectiveStdenv.hostPlatform.system == "aarch64-linux") ''
    # https://github.com/NixOS/nixpkgs/pull/226734#issuecomment-1663028691
    rm -v onnxruntime/test/optimizer/nhwc_transformer_test.cc
  '';

  preConfigure = lib.optionalString rocmSupport ''
    # Create symlinks for ROCm tools that HIP compiler expects
    mkdir -p /tmp/rocm/bin /tmp/rocm/lib/llvm/bin
    ln -sf ${rocmPackages.rocm-core}/bin/rocm_agent_enumerator /tmp/rocm/bin/rocm_agent_enumerator
    ln -sf ${rocmPackages.llvm.clang}/bin/clang++ /tmp/rocm/lib/llvm/bin/clang++
    ln -sf ${rocmPackages.llvm.clang}/bin/clang /tmp/rocm/lib/llvm/bin/clang
    export ROCM_PATH=/tmp/rocm
    export ROCM_DEVICE_LIB_PATH=${rocmPackages.rocm-device-libs}/lib
  '';

  postBuild = lib.optionalString pythonSupport ''
    ${python3Packages.python.interpreter} ../setup.py bdist_wheel
  '';

  postInstall = ''
    # perform parts of `tools/ci_build/github/linux/copy_strip_binary.sh`
    install -m644 -Dt $out/include \
      ../include/onnxruntime/core/framework/provider_options.h \
      ../include/onnxruntime/core/providers/cpu/cpu_provider_factory.h \
      ../include/onnxruntime/core/session/onnxruntime_*.h
  '';

  passthru = {
    inherit cudaSupport cudaPackages; # for the python module
    inherit rocmSupport rocmPackages rcclSupport; # for the python module
    inherit protobuf;
    tests = lib.optionalAttrs pythonSupport {
      python = python3Packages.onnxruntime;
    };
  };

  meta = {
    description = "Cross-platform, high performance scoring engine for ML models";
    longDescription = ''
      ONNX Runtime is a performance-focused complete scoring engine
      for Open Neural Network Exchange (ONNX) models, with an open
      extensible architecture to continually address the latest developments
      in AI and Deep Learning. ONNX Runtime stays up to date with the ONNX
      standard with complete implementation of all ONNX operators, and
      supports all ONNX releases (1.2+) with both future and backwards
      compatibility.
    '';
    homepage = "https://github.com/microsoft/onnxruntime";
    changelog = "https://github.com/microsoft/onnxruntime/releases/tag/v${version}";
    # https://github.com/microsoft/onnxruntime/blob/master/BUILD.md#architectures
    platforms = lib.platforms.unix;
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      puffnfresh
      ck3d
    ];
  };
}
