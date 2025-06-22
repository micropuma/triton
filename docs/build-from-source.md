# 源码编译（LLVM, Triton source code源码编译）

这种编译方式其实就是第二种源码编译方式的c++部分编译（triton底层代码）。这种源码编译方式主要是为了triton c++部分代码开发提供支持，详细流程参考[Triton Development guide](https://www.lei.chat/posts/triton-compiler-development-tips/)。主要构建流程如下：

* 虚拟环境配置（主要install pybind11）

* git clone指定版本的triton和llvm

  ```shell
  cd ./triton-workspace
  git clone git@github.com:micropuma/triton.git
  git clone git@github.com:llvm/llvm-project.git
  cd llvm-project
  git checkout 8957e64a20fc7f4277565c6cfe3e555c119783ce  # 对应版本参考cmake/llvm-hash.txt
  ```

* 源码编译llvm，使用如下脚本：

  ```shell
  #!/bin/bash
  # 脚本名称：configure_mlir.sh
  # 功能：配置并生成LLVM/MLIR的Ninja构建文件
  # 参数：<source-dir> <target-dir> <build-type>
  # 示例：./configure_mlir.sh llvm-project/llvm build/mlir-debug Debug
  
  # 严格模式：遇到错误立即退出，未定义变量报错
  set -euo pipefail
  
  # 参数校验
  if [ $# -lt 3 ]; then
      echo "错误：参数不足"
      echo "用法：$0 <source-dir> <target-dir> <build-type>"
      echo "示例：$0 llvm-project/llvm build/mlir Debug"
      exit 1
  fi
  
  SOURCE_DIR="$1"
  TARGET_DIR="$2"
  BUILD_TYPE="$3"
  
  # 检查CMake是否安装
  if ! command -v cmake &> /dev/null; then
      echo "错误：未找到CMake，请先安装CMake"
      exit 1
  fi
  
  # 检查Clang编译器
  if ! command -v clang &> /dev/null || ! command -v clang++ &> /dev/null; then
      echo "警告：未找到Clang编译器，将使用系统默认编译器"
      CLANG_CC=""
      CLANG_CXX=""
  else
      CLANG_CC="$(which clang)"
      CLANG_CXX="$(which clang++)"
  fi
  
  # 创建目标目录（如果不存在）
  mkdir -p "$TARGET_DIR"
  
  # 执行CMake配置
  cmake -GNinja \
      -S "$SOURCE_DIR" \
      -B "$TARGET_DIR" \
      -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      ${CLANG_CC:+-DCMAKE_C_COMPILER="$CLANG_CC"} \
      ${CLANG_CXX:+-DCMAKE_CXX_COMPILER="$CLANG_CXX"} \
      -DLLVM_ENABLE_PROJECTS="llvm;mlir" \
      -DLLVM_TARGETS_TO_BUILD="AMDGPU;NVPTX;X86;AArch64"
  
  echo "✅ 配置成功！构建目录：$TARGET_DIR"
  echo "➜ 编译命令：cmake --build $TARGET_DIR -j $(nproc)"
  ```

  这个脚本十分详细，根据脚本的参数要求源码编译即可

* Triton源码编译同理

  ```shell
  #!/bin/bash
  # Triton CMake 配置脚本
  # 用法: ./triton_configure.sh <source-dir> <target-dir> <build-type> <mlir-dir>
  
  # 参数校验
  if [ $# -lt 4 ]; then
      echo "错误：参数不足"
      echo "用法: $0 <source-dir> <target-dir> <build-type> <mlir-dir>"
      echo "示例: $0 triton build/triton-debug Debug build/mlir-debug"
      exit 1
  fi
  
  SOURCE_DIR="$1"
  TARGET_DIR="$2"
  BUILD_TYPE="$3"
  MLIR_DIR="$4"
  
  # 检查必要工具
  check_dependency() {
      if ! command -v "$1" &> /dev/null; then
          echo "错误：未安装 $1，请先安装: $2"
          exit 1
      fi
  }
  check_dependency cmake "https://cmake.org/install/"
  check_dependency ninja "https://ninja-build.org/"
  check_dependency clang "https://llvm.org/"
  
  # 跨平台链接器配置
  if [[ "$(uname)" == "Darwin" ]]; then
      LINKER_FLAGS=()
  else
      LINKER_FLAGS=(
          "-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld"
          "-DCMAKE_MODULE_LINKER_FLAGS=-fuse-ld=lld"
          "-DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=lld"
      )
      check_dependency lld "sudo apt install lld"
  fi
  
  # 获取 Triton 仓库根目录
  REPO_BASE_DIR=$(git -C "$SOURCE_DIR" rev-parse --show-toplevel 2>/dev/null)
  if [ $? -ne 0 ]; then
      echo "错误：$SOURCE_DIR 不是有效的 Git 仓库"
      exit 1
  fi
  
  # 创建目标目录
  mkdir -p "$TARGET_DIR" || { echo "无法创建目录: $TARGET_DIR"; exit 1; }
  
  # 执行 CMake 配置
  cmake -GNinja \
      -S "$SOURCE_DIR" \
      -B "$TARGET_DIR" \
      -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -DTRITON_CODEGEN_BACKENDS="amd;nvidia" \
      -DLLVM_INCLUDE_DIRS="$MLIR_DIR/include" \
      -DLLVM_LIBRARY_DIR="$MLIR_DIR/lib" \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_LINKER=lld \
      "${LINKER_FLAGS[@]}" \
      -DCMAKE_C_COMPILER_LAUNCHER=ccache \
      -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
      -DTRITON_BUILD_PYTHON_MODULE=ON \
      -DTRITON_BUILD_PROTON=ON \
      -DCUPTI_INCLUDE_DIR="$REPO_BASE_DIR/third_party/nvidia/backend/include" \
      -DROCTRACER_INCLUDE_DIR="$REPO_BASE_DIR/third_party/amd/backend/include" \
      -DJSON_INCLUDE_DIR="$HOME/.triton/json/include" \
      -DLLVM_SYSPATH=/mnt/home/douliyang/triton-workspace/triton-dly-repo/build/mlir-debug \
      -DTRITON_WHEEL_DIR=/mnt/home/douliyang/triton-workspace/triton-dly-repo/build/wheel
  
  echo "✅ Triton CMake 配置成功！"
  echo "➜ 编译命令: cmake --build $TARGET_DIR -j$(nproc)"
  ```

* 支持vscode 跳转

  ```shell
  # 在triton的源码目录下运行
  ln -s ../build/triton-debug/compile_commands.json ./
  ```

