{ stdenv, buildBazelPackage, lib, fetchFromGitHub, fetchpatch, symlinkJoin
, buildPythonPackage, isPy3k, pythonOlder, pythonAtLeast
, which, swig, binutils, glibcLocales
, python, jemalloc, openmpi
, numpy, six, protobuf, tensorflow-tensorboard, backports_weakref, mock, enum34
, xlaSupport ? true
, cudaSupport ? false, nvidia_x11 ? null, cudatoolkit ? null, cudnn ? null
# Default from ./configure script
, cudaCapabilities ? [ "3.5" "5.2" ]
, sse42Support ? false
, avx2Support ? false
, fmaSupport ? false
}:

assert cudaSupport -> nvidia_x11 != null
                   && cudatoolkit != null
                   && cudnn != null;

# unsupported combination
assert ! (stdenv.isDarwin && cudaSupport);

let

  withTensorboard = pythonOlder "3.6";

  cudatoolkit_joined = symlinkJoin {
    name = "${cudatoolkit.name}-unsplit";
    paths = [ cudatoolkit.out cudatoolkit.lib ];
  };

  tfFeature = x: if x then "1" else "0";

  version = "1.4.0";

  pkg = buildBazelPackage rec {
    name = "tensorflow-build-${version}";

    src = fetchFromGitHub {
      owner = "tensorflow";
      repo = "tensorflow";
      rev = "v${version}";
      sha256 = "1h4y1kpy34k354shspaxazkas81mylnvg6h9qxz23ywvrqqsv049";
    };

    nativeBuildInputs = [ swig which ];

    buildInputs = [ python jemalloc openmpi glibcLocales numpy ]
      ++ lib.optionals cudaSupport [ cudatoolkit cudnn nvidia_x11 ];

    preConfigure = ''
      patchShebangs configure

      export PYTHON_BIN_PATH="${python.interpreter}"
      export PYTHON_LIB_PATH="$NIX_BUILD_TOP/site-packages"
      export TF_NEED_GCP=1
      export TF_NEED_HDFS=1
      export TF_ENABLE_XLA=${tfFeature xlaSupport}
      export CC_OPT_FLAGS=" "
      # https://github.com/tensorflow/tensorflow/issues/14454
      export TF_NEED_MPI=${tfFeature cudaSupport}
      export TF_NEED_CUDA=${tfFeature cudaSupport}
      ${lib.optionalString cudaSupport ''
        export CUDA_TOOLKIT_PATH=${cudatoolkit_joined}
        export TF_CUDA_VERSION=${cudatoolkit.majorVersion}
        export CUDNN_INSTALL_PATH=${cudnn}
        export TF_CUDNN_VERSION=${cudnn.majorVersion}
        export GCC_HOST_COMPILER_PATH=${cudatoolkit.cc}/bin/gcc
        export TF_CUDA_COMPUTE_CAPABILITIES=${lib.concatStringsSep "," cudaCapabilities}
      ''}

      mkdir -p "$PYTHON_LIB_PATH"
    '';

    NIX_CFLAGS_COMPILE = cudatoolkit.ccFlags;
    NIX_LDFLAGS = lib.optionals cudaSupport [ "-lcublas" "-lcudnn" "-lcuda" "-lcudart" ];

    hardeningDisable = [ "all" ];

    bazelFlags = [ "--config=opt" ]
                 ++ lib.optional sse42Support "--copt=-msse4.2"
                 ++ lib.optional avx2Support "--copt=-mavx2"
                 ++ lib.optional fmaSupport "--copt=-mfma"
                 ++ lib.optional cudaSupport "--config=cuda";

    bazelTarget = "//tensorflow/tools/pip_package:build_pip_package";

    fetchAttrs = {
      preInstall = ''
        rm -rf $bazelOut/external/{bazel_tools,\@bazel_tools.marker,local_*,\@local_*}
      '';

      sha256 = "0sq0a7vsajzqwxgg82xw1q74n7vdq37n9d5z7p0c8gzpmyw7mgc9";
    };

    buildAttrs = {
      preBuild = ''
        patchShebangs .
        find -type f -name CROSSTOOL\* -exec sed -i \
          -e 's,/usr/bin/ar,${binutils}/bin/ar,g' \
          {} \;
      '';

      installPhase = ''
        sed -i 's,.*bdist_wheel.*,cp -rL . "$out"; exit 0,' bazel-bin/tensorflow/tools/pip_package/build_pip_package 
        bazel-bin/tensorflow/tools/pip_package/build_pip_package $PWD/dist
      '';
    };

    dontFixup = true;
  };

in buildPythonPackage {
  name = "tensorflow-${version}";
  inherit version;

  src = pkg;

  installFlags = lib.optional (!withTensorboard) "--no-dependencies";

  # Tests are slow and impure.
  doCheck = false;

  postPatch = lib.optionalString (pythonAtLeast "3.4") ''
    sed -i '/enum34/d' setup.py
  '';

  propagatedBuildInputs = [ numpy six protobuf ]
                 ++ lib.optional (!isPy3k) mock
                 ++ lib.optionals (pythonOlder "3.4") [ backports_weakref enum34 ]
                 ++ lib.optional withTensorboard tensorflow-tensorboard;

  # For some reason, CUDA is not retained in RPATH.
  doInstallCheck = true;
  installCheckPhase = ''
    ${python.interpreter} -c "import tensorflow"
  '';

  meta = with stdenv.lib; {
    description = "Computation using data flow graphs for scalable machine learning";
    homepage = "http://tensorflow.org";
    license = licenses.asl20;
    maintainers = with maintainers; [ jyp abbradar ];
    platforms = with platforms; if cudaSupport then linux else linux ++ darwin;
  };
}
