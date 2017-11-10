{ stdenv, lib, fetchPypi, buildPythonPackage, isPy3k
, bleach_1_5_0
, numpy
, werkzeug
, protobuf
, markdown
, futures
}:

# tensorflow is built from a downloaded wheel, because the upstream
# project's build system is an arcane beast based on
# bazel. Untangling it and building the wheel from source is an open
# problem.

buildPythonPackage rec {
  pname = "tensorflow-tensorboard";
  version = "0.4.0rc2";
  name = "${pname}-${version}";
  format = "wheel";

  src = fetchPypi ({
    pname = "tensorflow_tensorboard";
    inherit version;
    format = "wheel";
  } // (if isPy3k then {
    python = "py3";
    sha256 = "0cv9r2dqp0hy85qs7l2986ifdx86q98xxc5w6xyp6hnkz2h6jcim";
  } else {
    python = "py2";
    sha256 = "0n71frdcwl44birwxdrvjdjhhg87awwv6syy65d2a13ivw87nya0";
  }));

  propagatedBuildInputs = [ bleach_1_5_0 numpy werkzeug protobuf markdown ] ++ lib.optional (!isPy3k) futures;

  meta = with stdenv.lib; {
    description = "TensorFlow helps the tensors flow";
    homepage = http://tensorflow.org;
    license = licenses.asl20;
    maintainers = with maintainers; [ abbradar ];
  };
}
