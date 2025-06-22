# 开启虚拟环境
virtualenv .venv
source .venv/bin/activate

# 安装依赖
pip install -r python/requirements.txt

# 源码构建好的LLVM路径
export LLVM_BUILD_DIR=/mnt/home/douliyang/triton-workspace/triton-dly-repo/build/mlir-debug 

LLVM_INCLUDE_DIRS=$LLVM_BUILD_DIR/include \
LLVM_LIBRARY_DIR=$LLVM_BUILD_DIR/lib \
LLVM_SYSPATH=$LLVM_BUILD_DIR \
    pip install -e . -i https://pypi.tuna.tsinghua.edu.cn/simple