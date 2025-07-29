# .ide/Dockerfile
FROM python:3.12.11-bookworm

# 以及按需安装其他软件
# RUN apt-get update && apt-get install -y git

# 安装 ssh 服务(用于支持 VSCode 客户端通过 Remote-SSH 访问开发环境);
# libxml2-utils 为 Google WebP 工具包，可用于命令行 webp 处理(cwebp)
RUN apt update && \
    apt install -y \
    git git-lfs \
    webp \
    wget \
    unzip \
    openssh-server \
    vim \
    zsh \
    zip \
    jq \
    libxml2-utils && \
    chsh -s /bin/zsh && \
    yes | zsh -c "$(curl -fsSL 'https://cnb.cool/Mintimate/tool-forge/oh-my-zsh/-/git/raw/main/AutoInstallZshWithPlugin.sh')"

# 安装 code-server 和 vscode 常用插件
RUN curl -fsSL https://code-server.dev/install.sh | sh \
  && code-server --install-extension redhat.vscode-yaml \
  && code-server --install-extension dbaeumer.vscode-eslint \
  && code-server --install-extension eamodio.gitlens \
  && code-server --install-extension ms-python.python \
  && echo done

# 修改 code-server 配置
RUN jq '.linkProtectionTrustedDomains |= . + ["https://marketplace.visualstudio.com"] | .extensionsGallery = { "serviceUrl": "https://marketplace.visualstudio.com/_apis/public/gallery", "cacheUrl": "https://vscode.blob.core.windows.net/gallery/index", "itemUrl": "https://marketplace.visualstudio.com/items", "controlUrl": "", "recommendationsUrl": "" }' /usr/lib/code-server/lib/vscode/product.json > /tmp/product.json.tmp && mv /tmp/product.json.tmp /usr/lib/code-server/lib/vscode/product.json

# 安装 AI 插件
RUN code-server --install-extension github.copilot

# 安装字体
RUN wget https://github.com/lxgw/LxgwWenKai/releases/download/v1.520/lxgw-wenkai-v1.520.zip && \
    unzip lxgw-wenkai-v1.520.zip && \
    mv lxgw-wenkai-v1.520 /usr/share/fonts/truetype && \
    rm lxgw-wenkai-v1.520.zip && \
    fc-cache -fv && \
    echo "done"

# 指定字符集支持命令行输入中文（根据需要选择字符集）
ENV LANG zh_CN.UTF-8
ENV LC_ALL zh_CN.UTF-8