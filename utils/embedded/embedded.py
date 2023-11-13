import argparse
import os
from pathlib import Path
import json
import platform
import subprocess
import shutil
from distutils.dir_util import copy_tree

class Configuration:
  def __init__(self, name, target, root_dir):
    self.target_settings = target
    self.name = name
    self.root_dir = root_dir
    self.triple = target["build"]["target"]
    self.arch = target["build"]["arch"]
    self.product_name = name + ".artifactbundle"
    self.build_mode_name = "Ninja-Release"
    self.cflags = target["build"]["cflags"]
    self.linker_script_name = target["build"]["linker-script"]

    cwd = Path(os.getcwd())
    self.build_dir = cwd / "build"
    self.build_mode_dir = self.build_dir / self.build_mode_name
    self.swift_toolchain_product = self.build_dir / "swift-toolchain"
    # TODO: Verify this on linux... it is probably incorrect
    self.swift_toolchain_product_path = self.swift_toolchain_product / "Applications" / "Xcode.app" / "Contents" / "Developer" / "Toolchains" / "XcodeDefault.xctoolchain"
    self.peer_dir = root_dir.parents[2]
    self.swift_source_dir = root_dir.parents[1]
    self.swift_utils_dir = self.swift_source_dir / "utils"
    self.swift_build_script = self.swift_utils_dir / "build-script"
    self.llvm_source_dir = self.peer_dir / "llvm-project"

    system = platform.system()
    machine = platform.machine()

    if system == "Darwin":
      system = "macosx"
      self.host = machine + "-apple-macosx14.0"
    else:
      raise ValueError("Linux hosts currently unsupported")
    # TODO: Add other system conversions

    llvm_build_name = "llvm-" + system + "-" + machine

    self.llvm_build_dir = self.build_mode_dir / llvm_build_name

    self.llvm_ar = self.llvm_build_dir / "bin" / "llvm-ar"
    self.clang = self.llvm_build_dir / "bin" / "clang"
    self.llvm_nm = self.llvm_build_dir / "bin" / "llvm-nm"
    self.llvm_ranlib = self.llvm_build_dir / "bin" / "llvm-ranlib"
    self.llvm_config = self.llvm_build_dir / "bin" / "llvm-config"

    self.compiler_rt_source_dir = self.llvm_source_dir / "compiler-rt"
    self.compiler_rt_build_dir = self.build_mode_dir / "compiler-rt"

    self.picolibc_source_dir = self.peer_dir / "picolibc"
    self.picolibc_build_dir = self.build_mode_dir / self.triple / "picolibc"

    self.sysroot_build_dir = self.build_mode_dir / self.triple / self.name
    
    self.sysroot_build_dir = self.build_mode_dir / self.name
    self.artifact_bundle = self.build_dir / self.product_name

    self.info_json = self.root_dir / "info.json"
    self.swift_sdk_json = self.root_dir / "swift-sdk.json"
    self.toolset_json = self.root_dir / "toolset.json"

    self.linker_script = self.root_dir / "linker-scripts" / self.linker_script_name

    self.compiler_rt_product = self.compiler_rt_build_dir / "lib" / "generic" / target["compiler-rt"]["product"]

    self.installed_info_json = self.artifact_bundle / "info.json"
    self.installed_target_dir = self.artifact_bundle / self.name / self.triple
    self.installed_swift_sdk_json = self.installed_target_dir / "swift-sdk.json"
    self.installed_toolset_json = self.installed_target_dir / "toolset.json"
    self.installed_toolchain = self.installed_target_dir / "swift.xctoolchain"
    self.installed_toolchain_baremetal = self.installed_toolchain / "usr" / "lib" / "clang" / "17" / "lib" / "baremetal"
    self.installed_compiler_rt_product = self.installed_toolchain_baremetal / target["compiler-rt"]["installed"]

    self.installed_sysroot_dir = self.installed_target_dir / "sdk"
    self.installed_sysroot_lib_dir = self.installed_sysroot_dir / "lib"

    self.installed_linker_script= self.installed_sysroot_lib_dir / self.linker_script_name

    self.compiler_rt_cmake_settings = target["compiler-rt"]["cmake"]
    config_name = target["picolibc"]["meson"]["config"]
    self.picolibc_meson_config_template = self.root_dir / "configs" / config_name
    self.build_picolibc_meson_config = self.picolibc_build_dir / config_name

  def populate(self, input):
    result = input.replace("%NAME%", self.name)
    result = result.replace("%HOST%", self.host)
    result = result.replace("%TARGET%", self.triple)
    result = result.replace("%C_FLAGS_ARRAY%", "\", \"".join(self.cflags))
    result = result.replace("%LINKER_SCRIPT_NAME%", self.linker_script_name)
    result = result.replace("%LLVM_BUILD_DIR%", str(self.llvm_build_dir))
    return result

  def template(self, input, output):
    with open(str(input), "r") as f:
      contents = f.read()
      stream = open(str(output), "w")
      stream.write(self.populate(contents))
      stream.close()

def run_cmake(build_directory: Path, source_directory: Path, settings, configuration: Configuration, install: bool = False):
  arguments = ["cmake", str(source_directory), "-G", "Ninja"]
  defaultSettings = {
    "CMAKE_SYSTEM_NAME": "Generic",
    "CMAKE_TRY_COMPILE_TARGET_TYPE": "STATIC_LIBRARY",
    "CMAKE_AR": str(configuration.llvm_ar),
    "CMAKE_C_COMPILER": str(configuration.clang),
    "CMAKE_NM": str(configuration.llvm_nm),
    "CMAKE_RANLIB": str(configuration.llvm_ranlib),
    "LLVM_CONFIG_PATH": str(configuration.llvm_config),
  }
  for parameter, value in defaultSettings.items():
    arguments.append("-D" + parameter + "=" + value)
  for parameter, value in settings.items():
    arguments.append("-D" + parameter + "=" + value)

  build_directory.mkdir(parents=True, exist_ok=True)
  subprocess.run(arguments, cwd=str(build_directory))
  if install:
    subprocess.run(["ninja", "install"], cwd=str(build_directory), check=True)
  else:
    subprocess.run(["ninja"], cwd=str(build_directory), check=True)

def build_swift(configuration: Configuration):
  subprocess.run([
    str(configuration.swift_build_script), "-R",
    "--llvm-targets-to-build", "all",
    "--llvm-install-components", "llvm-ar;llvm-cov;llvm-profdata;llvm-readobj;llvm-readelf;llvm-ranlib;llvm-strip;llvm-objcopy;IndexStore;clang;clang-resource-headers;compiler-rt;clangd;LTO;lld",
    "--swiftpm", "true",
    "--swift-driver", "true",
    "--install-swift-driver", "true",
    "--install-destdir", str(configuration.swift_toolchain_product), 
    "--install-all", "true", 
    "--skip-ios",
    "--skip-tvos",
    "--skip-watchos", 
    "--playgroundsupport", "false",
    "--toolchain-benchmarks", "false",
    "--skip-build-benchmarks", "true",
    "--skip-test-toolchain-benchmarks", "true",
    "--llbuild", "true",
    "--build-lld", "true",
    "--build-stdlib-deployment-targets", "all",
    "--no-assertions"
  ], check=True)

def build_compiler_rt(configuration: Configuration):
  run_cmake(configuration.compiler_rt_build_dir, configuration.compiler_rt_source_dir, configuration.compiler_rt_cmake_settings, configuration)

def build_libc(configuration: Configuration):
  configuration.picolibc_build_dir.mkdir(parents=True, exist_ok=True)
  configuration.sysroot_build_dir.mkdir(parents=True, exist_ok=True)
  configuration.template(configuration.picolibc_meson_config_template, configuration.build_picolibc_meson_config)
  subprocess.run([
    "meson", "setup",
    "-Dincludedir=include",
    "-Dlibdir=lib",
    "-Dtests-enable-stack-protector=false",
    "-Dtests-enable-full-malloc-stress=false",
    "-Dmultilib=false",
    "--cross-file", str(configuration.build_picolibc_meson_config),
    "--prefix", str(configuration.sysroot_build_dir),
    "./",
    str(configuration.picolibc_source_dir)
  ], cwd=str(configuration.picolibc_build_dir), check=True)
  subprocess.run([
    "ninja", "install"
  ], cwd=str(configuration.picolibc_build_dir), check=True)

def build_artifactbundle(configuration: Configuration):
  configuration.artifact_bundle.mkdir(parents=True, exist_ok=True)
  configuration.installed_target_dir.mkdir(parents=True, exist_ok=True)
  
  configuration.template(configuration.info_json, configuration.installed_info_json)
  configuration.template(configuration.swift_sdk_json, configuration.installed_swift_sdk_json)
  configuration.template(configuration.toolset_json, configuration.installed_toolset_json)
  
  copy_tree(str(configuration.swift_toolchain_product_path), str(configuration.installed_toolchain))
  configuration.installed_toolchain_baremetal.mkdir(parents=True, exist_ok=True)
  shutil.copyfile(str(configuration.compiler_rt_product), str(configuration.installed_compiler_rt_product))

  copy_tree(str(configuration.sysroot_build_dir / "include"), str(configuration.installed_sysroot_dir / "include"))
  copy_tree(str(configuration.sysroot_build_dir / "lib"), str(configuration.installed_sysroot_dir / "lib"))

  shutil.copyfile(str(configuration.linker_script), str(configuration.installed_linker_script))

  rt_dir = configuration.installed_toolchain / "usr" / "lib" / "swift" / configuration.arch
  rt_dir.mkdir(parents=True, exist_ok=True)
  subprocess.run([
    str(configuration.clang), 
    "-target", configuration.triple
  ] + configuration.cflags + [
    "-I" + str(configuration.installed_sysroot_dir / "include"),
    "-c", str(configuration.root_dir / "swiftrt_stub.c"),
    "-o", str(rt_dir / "swiftrt.o")
  ], check=True)

def install_artifactbundle(configuration: Configuration):
  subprocess.run([
    "swift", "experimental-sdk", "remove", configuration.name
  ])
  subprocess.run([
    "swift", "experimental-sdk", "install", str(configuration.artifact_bundle)
  ], check=True)

def main():
  root_dir = Path(__file__).resolve().parents[0]
  
  targets_json = root_dir / "targets.json"

  with open(str(targets_json)) as f:
    targets = json.load(f)

  parser = argparse.ArgumentParser()
  parser.add_argument("--target", choices=targets.keys(), help="Configured target to build an embedded toolchain for.")
  parser.add_argument("--skip-swift", default=False, action='store_true')
  parser.add_argument("--skip-compiler-rt", default=False, action='store_true')
  parser.add_argument("--skip-libc", default=False, action='store_true')
  parser.add_argument("--install", default=False, action='store_true')
  args = parser.parse_args()

  target_name = args.target
  target = targets[target_name]
  config = Configuration(target_name, target, root_dir)

  print("Building %s" % config.product_name)
  
  if not args.skip_swift:
    build_swift(config)
  if not args.skip_compiler_rt:
    build_compiler_rt(config)
  if not args.skip_libc:
    build_libc(config)
  build_artifactbundle(config)
  if args.install:
    install_artifactbundle(config)

