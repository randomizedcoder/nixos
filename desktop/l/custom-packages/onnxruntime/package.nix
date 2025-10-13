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
, git
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

  # IMPORTANT: CUDA and ROCm support are mutually exclusive in onnxruntime
  # - cudaSupport: Enable CUDA support for NVIDIA GPUs
  # - ncclSupport: Enable NCCL for CUDA multi-GPU support (requires cudaSupport)
  # - rocmSupport: Enable ROCm support for AMD GPUs
  # - rcclSupport: Enable RCCL for ROCm multi-GPU support (requires rocmSupport)
  # Only one of (cudaSupport, rocmSupport) can be true at a time

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

  composable_kernel = fetchFromGitHub {
    owner = "ROCm";
    repo = "composable_kernel";
    tag = "rocm-6.3.3";
    hash = "sha256-XIzoiFkUyQ8VsqsQFg8HVbDRdP8vZF527OpBGbBU2j0=";
  };

         isCudaJetson = cudaSupport && cudaPackages.flags.isJetsonBuild;

         # Validate that CUDA and ROCm are not both enabled
         _ = if cudaSupport && rocmSupport then
           throw ''
             onnxruntime: CUDA and ROCm support cannot be enabled simultaneously.

             Current configuration:
               - cudaSupport = ${toString cudaSupport}
               - rocmSupport = ${toString rocmSupport}

             Please choose either:
               - For NVIDIA GPUs: cudaSupport = true, rocmSupport = false
               - For AMD GPUs: cudaSupport = false, rocmSupport = true
           ''
         else if cudaSupport && rcclSupport then
           throw "onnxruntime: RCCL support requires ROCm support, but CUDA is enabled. Please disable CUDA or enable ROCm."
         else if rocmSupport && ncclSupport then
           throw "onnxruntime: NCCL support requires CUDA support, but ROCm is enabled. Please disable ROCm or enable CUDA."
         else null;
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
    git
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
    rocmPackages.rocm-core
    rocmPackages.rocmPath
    rocmPackages.rocminfo
    rocmPackages.clr
    rocmPackages.rocm-comgr
    rocmPackages.hip-common
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
      clr
      rocm-comgr
      hip-common
      hipcub
      rocprim
      hipblas
      rocblas
      miopen
      rocfft
      rocsparse
      hiprand
      rocrand
      hipfft
      roctracer
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
           # ROCm version information for CMake
           (lib.cmakeFeature "ROCM_VERSION" "6.3.3")
           (lib.cmakeFeature "ROCM_VERSION_MAJOR" "6")
           (lib.cmakeFeature "ROCM_VERSION_MINOR" "3")
           (lib.cmakeFeature "ROCM_VERSION_PATCH" "3")
           # Point onnxruntime to our custom ROCm build directory using absolute path
           (lib.cmakeFeature "onnxruntime_ROCM_HOME" "/build/source/rocm-6.3.3")
           # Comprehensive AMD GPU architecture support:
           # MI Cards: gfx900 (MI25/Vega 10), gfx906 (MI50/MI60/Vega 20), gfx908 (MI100/CDNA), gfx90a (MI200/CDNA2), gfx942 (MI300/CDNA3)
           # RDNA Cards: gfx1010 (RX 5700/Navi 10), gfx1011 (Pro 5600M/Navi 12), gfx1012 (RX 5500/Navi 14), gfx1020 (Navi 21 early), gfx1030 (RX 6800/6900/Navi 21/22), gfx1100 (RX 7900/Navi 31)
           (lib.cmakeFeature "CMAKE_HIP_ARCHITECTURES" "gfx900;gfx906;gfx908;gfx90a;gfx942;gfx1010;gfx1011;gfx1012;gfx1020;gfx1030;gfx1100")
           (lib.cmakeFeature "HIP_COMPILER" "${rocmPackages.hipcc}/bin/hipcc")
           (lib.cmakeFeature "CMAKE_CXX_COMPILER" "${rocmPackages.hipcc}/bin/hipcc")
           (lib.cmakeFeature "CMAKE_HIP_COMPILER" "${rocmPackages.llvm.clang}/bin/clang++")
             # External dependencies for ROCm
             (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_COMPOSABLE_KERNEL" "${composable_kernel}")
             # Fix composable_kernel path for generate.py script
             (lib.cmakeFeature "CK_TILE_FMHA_GENERATE_PY" "${composable_kernel}/example/ck_tile/01_fmha/generate.py")
         ];

         env = lib.optionalAttrs effectiveStdenv.cc.isClang {
           NIX_CFLAGS_COMPILE = "-Wno-error";
         } // lib.optionalAttrs rocmSupport {
           # ROCm environment variables for HIP compiler - using Nix store paths
           ROCM_PATH = "${rocmPackages.rocm-core}";
           ROCM_HOME = "${rocmPackages.rocm-core}";
           HIP_PATH = "${rocmPackages.hipcc}";
           HIP_CLANG_PATH = "${rocmPackages.llvm.clang}/bin";
           HSA_PATH = "${rocmPackages.rocm-core}";
           HIP_PLATFORM = "amd";
           HIP_COMPILER = "clang";
           HIP_RUNTIME = "rocclr";
           # ROCm device library path
           ROCM_DEVICE_LIB_PATH = "${rocmPackages.rocm-device-libs}/lib";
           # ROCm version information for CMake detection
           ROCM_VERSION = "6.3.3";
           ROCM_VERSION_MAJOR = "6";
           ROCM_VERSION_MINOR = "3";
           ROCM_VERSION_PATCH = "3";
           # Additional paths for HIP compiler - using Nix store paths
           PATH = "${rocmPackages.rocmPath}/bin:${rocmPackages.rocm-core}/bin:${rocmPackages.llvm.clang}/bin:$PATH";
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
           # Debug: Show ROCm environment variables (set via env attribute)
           echo "ROCm environment variables:"
           echo "ROCM_PATH=$ROCM_PATH"
           echo "ROCM_DEVICE_LIB_PATH=$ROCM_DEVICE_LIB_PATH"
           echo "HIP_PATH=$HIP_PATH"
           echo "HIP_CLANG_PATH=$HIP_CLANG_PATH"
           echo "HSA_PATH=$HSA_PATH"
           echo "PATH=$PATH"

           # Create a custom ROCm directory structure in the build directory
           # since we can't write to the Nix store
           ROCM_BUILD_DIR=$PWD/rocm-6.3.3
           mkdir -p $ROCM_BUILD_DIR/share/rocm/.info
           mkdir -p $ROCM_BUILD_DIR/.info
           mkdir -p $ROCM_BUILD_DIR/lib/cmake/rocm
           mkdir -p $ROCM_BUILD_DIR/include/rocm
           mkdir -p $ROCM_BUILD_DIR/include/rocm-core

           # Create version files in the build directory (onnxruntime looks for these specific files)
           echo "6.3.3" > $ROCM_BUILD_DIR/version
           echo "6.3.3-0" > $ROCM_BUILD_DIR/.info/version
           echo "6.3.3" > $ROCM_BUILD_DIR/share/rocm/version
           echo "6.3.3" > $ROCM_BUILD_DIR/share/rocm/.info/version

           # Create CMake version file
           cat > $ROCM_BUILD_DIR/lib/cmake/rocm/rocm-config-version.cmake << 'EOF'
           set(PACKAGE_VERSION "6.3.3")
           set(PACKAGE_VERSION_MAJOR "6")
           set(PACKAGE_VERSION_MINOR "3")
           set(PACKAGE_VERSION_PATCH "3")
           EOF

             # Create rocm-config.cmake file
             cat > $ROCM_BUILD_DIR/lib/cmake/rocm/rocm-config.cmake << 'EOF'
             set(ROCM_VERSION "6.3.3")
             set(ROCM_VERSION_MAJOR "6")
             set(ROCM_VERSION_MINOR "3")
             set(ROCM_VERSION_PATCH "3")
             EOF

             # Create symlinks to ROCm CMake modules
             mkdir -p $ROCM_BUILD_DIR/share/rocm/cmake
             ln -sf "${rocmPackages.rocm-cmake}/share/rocm/cmake"/* $ROCM_BUILD_DIR/share/rocm/cmake/ 2>/dev/null || true

             # Debug: Show ROCm CMake modules
             echo "Debug: ROCm CMake modules from rocm-cmake package:"
             ls -la "${rocmPackages.rocm-cmake}/share/rocm/cmake/" || echo "No ROCm CMake modules found"
             echo "Debug: ROCm CMake modules in our build directory:"
             ls -la $ROCM_BUILD_DIR/share/rocm/cmake/ || echo "No ROCm CMake modules in build directory"

             # Debug: Show composable_kernel structure
             echo "Debug: Composable kernel source structure:"
             find "${composable_kernel}" -name "generate.py" -type f || echo "No generate.py found"
             find "${composable_kernel}" -path "*/example/ck_tile/01_fmha/*" -type f || echo "No 01_fmha files found"

             # Fix composable_kernel path issue - create symlink to expected location
             echo "Debug: Creating symlink for composable_kernel generate.py in preConfigure"
             mkdir -p $PWD/cmake/example/ck_tile/01_fmha
             ln -sf "${composable_kernel}/example/ck_tile/01_fmha/generate.py" $PWD/cmake/example/ck_tile/01_fmha/generate.py
             echo "Debug: Symlink created in preConfigure:"
             ls -la $PWD/cmake/example/ck_tile/01_fmha/generate.py || echo "Symlink creation failed in preConfigure"

           # Create rocm_version.h header files (onnxruntime looks for these)
           cat > $ROCM_BUILD_DIR/include/rocm_version.h << 'EOF'
#ifndef ROCM_VERSION_H
#define ROCM_VERSION_H
#define ROCM_VERSION_MAJOR 6
#define ROCM_VERSION_MINOR 3
#define ROCM_VERSION_PATCH 3
#define ROCM_VERSION_STRING "6.3.3"
#endif
EOF

             # Also create the rocm-core version
             cat > $ROCM_BUILD_DIR/include/rocm-core/rocm_version.h << 'EOF'
#ifndef ROCM_VERSION_H
#define ROCM_VERSION_H
#define ROCM_VERSION_MAJOR 6
#define ROCM_VERSION_MINOR 3
#define ROCM_VERSION_PATCH 3
#define ROCM_VERSION_STRING "6.3.3"
#endif
EOF

             # Create MIOPEN version.h file (onnxruntime looks for this)
             mkdir -p $ROCM_BUILD_DIR/include/miopen
             cat > $ROCM_BUILD_DIR/include/miopen/version.h << 'EOF'
#ifndef MIOPEN_VERSION_H
#define MIOPEN_VERSION_H
#define MIOPEN_VERSION_MAJOR 6
#define MIOPEN_VERSION_MINOR 3
#define MIOPEN_VERSION_PATCH 3
#define MIOPEN_VERSION_STRING "6.3.3"
#endif
EOF

           # Debug: Show what's in our include directory
           echo "Debug: Contents of include directory:"
           ls -la $ROCM_BUILD_DIR/include/ || echo "include directory not found"
           echo "Debug: Contents of include/rocm-core directory:"
           ls -la $ROCM_BUILD_DIR/include/rocm-core/ || echo "include/rocm-core directory not found"
           echo "Debug: Contents of include/miopen directory:"
           ls -la $ROCM_BUILD_DIR/include/miopen/ || echo "miopen directory not found"

           # Create symlinks to the actual ROCm tools in the Nix store
           mkdir -p $ROCM_BUILD_DIR/bin
           mkdir -p $ROCM_BUILD_DIR/llvm/bin
           ln -sf "${rocmPackages.hipcc}/bin/hipcc" $ROCM_BUILD_DIR/bin/hipcc
           ln -sf "${rocmPackages.llvm.clang}/bin/clang++" $ROCM_BUILD_DIR/llvm/bin/clang++
           ln -sf "${rocmPackages.llvm.clang}/bin/clang" $ROCM_BUILD_DIR/llvm/bin/clang
           ln -sf "${rocmPackages.rocmPath}/bin/rocm_agent_enumerator" $ROCM_BUILD_DIR/bin/rocm_agent_enumerator

           # Update environment variables to point to our build directory
           export ROCM_PATH=$ROCM_BUILD_DIR
           export CMAKE_PREFIX_PATH=$ROCM_BUILD_DIR:$CMAKE_PREFIX_PATH

           # Set the ROCM_HOME environment variable for CMake to use
           export ROCM_HOME=$ROCM_BUILD_DIR

           echo "Created ROCm build directory at: $ROCM_BUILD_DIR"
           echo "Updated ROCM_PATH to: $ROCM_PATH"
           echo "Set ROCM_HOME to: $ROCM_HOME"

           # Debug: Show the files we created
           echo "Debug: ROCm version files created:"
           ls -la $ROCM_BUILD_DIR/version || echo "version file not found"
           ls -la $ROCM_BUILD_DIR/.info/version || echo ".info/version file not found"
           ls -la $ROCM_BUILD_DIR/include/rocm-core/rocm_version.h || echo "rocm_version.h not found"

           # Debug: Show the symlinks we created
           echo "Debug: ROCm tool symlinks created:"
           ls -la $ROCM_BUILD_DIR/bin/hipcc || echo "hipcc symlink not found"
           ls -la $ROCM_BUILD_DIR/llvm/bin/clang++ || echo "clang++ symlink not found"
           ls -la $ROCM_BUILD_DIR/bin/rocm_agent_enumerator || echo "rocm_agent_enumerator symlink not found"

           # Debug: Show what onnxruntime will look for
           echo "Debug: onnxruntime_ROCM_HOME will be set to: /build/source/rocm-6.3.3"
           echo "Debug: This should point to our ROCm directory with version files"

           # Verify ROCm tools are accessible
           echo "Checking ROCm tools:"
           command -v rocm_agent_enumerator || echo "rocm_agent_enumerator not found"
           command -v hipcc || echo "hipcc not found"
           command -v clang++ || echo "clang++ not found"
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
