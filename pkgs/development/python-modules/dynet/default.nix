{ fetchurl, stdenv, buildPythonPackage, fetchPypi, pytest, cmake, cython, cudatoolkit, cudnn, symlinkJoin, python, numpy }:

let cudatoolkit_joined = symlinkJoin {
        name = "${cudatoolkit.name}-unsplit";
        paths = [ cudatoolkit.out cudatoolkit.lib ];
    };

    # dynet insists on using the source of eigen rather than an installed version (?!)
    eigenVersion = "2355b229ea4c";
    eigenDir = "eigen-eigen-${eigenVersion}";
    eigen = fetchurl {
               url = "http://bitbucket.org/eigen/eigen/get/${eigenVersion}.tar.gz";
               sha256 = "0kr1cy298sf2swzzq239xhkg6km9blh3hpbbzlnvy55m6ldb7b8c";
             };

in buildPythonPackage rec {
  pname = "dyNET";
  version = "2.0.3";
  name  = "${pname}-${version}";
  src = fetchPypi {
            inherit pname version;
            sha256 = "0xanrmf9m10w92361mqnbs3wyvsw1j3g567b8b40jrkgh44kj6yp";
            };

  sourceRoot = name;
  srcs = [ eigen src ];

  buildInputs = [ cmake cython ];
  propagatedBuildInputs = [ numpy ];
  buildPhase = ''
    mkdir build
    pushd build
    cmake .. -DBACKEND=eigen -DEIGEN3_INCLUDE_DIR="../../${eigenDir}" -DPYTHON="${python.interpreter}"
    # export CC=${cudatoolkit.cc}/bin/gcc
    # export CXX=${cudatoolkit.cc}/bin/g++
    # cmake .. -DBACKEND=cuda -DCUDA_TOOLKIT_ROOT_DIR=${cudatoolkit_joined}  -DEIGEN3_INCLUDE_DIR="../../${eigenDir}" -DPYTHON="${python.interpreter}"
    make -j6
    popd
  '';

  checkInputs = [ ];
  doCheck = false;

  installPhase = ''
    pushd  build/dynet
    mkdir -p "$out/dynet"
    install -t "$out/dynet" libdynet.so
    popd

    pushd build/python
    mkdir -p "$out/${python.sitePackages}"
    export PYTHONPATH="$out/${python.sitePackages}:$PYTHONPATH"
    # export INSTALL_PREFIX="$out"
    export PROJECT_BINARY_DIR="$out" # this is where the installed libdynet.so will link to.
    python ../../setup.py build --build-dir=.. --skip-build install --prefix="$out"
    popd
  '';

  LC_ALL="en_US.UTF-8";

  meta = with stdenv.lib; {
    description = "Dynet";
    homepage = "http://dynet.readthedocs.io";
    license = licenses.bsd3;
  };
}
