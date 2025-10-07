# 🛠️ ABCloudOps Scripts Kit

A collection of production-ready DevOps automation scripts for AWS, Azure, and cloud infrastructure management.

**Author:** Ahmed Belal  
**GitHub:** [@engabelal](https://github.com/engabelal)  
**LinkedIn:** [linkedin.com/in/engabelal](https://linkedin.com/in/engabelal)

---

## 📋 Table of Contents

- [Overview](#overview)
- [Scripts](#scripts)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Contributing](#contributing)
- [License](#license)

---

## 🎯 Overview

This toolkit provides battle-tested scripts for:
- ✅ **Cost Optimization** - Identify and eliminate wasteful cloud spending
- ✅ **Resource Management** - Automate cloud resource operations
- ✅ **Security Auditing** - Check compliance and security posture
- ✅ **Monitoring & Alerts** - Track infrastructure health
- ✅ **Backup & Recovery** - Automate backup operations

---

## 📦 Scripts

This repository contains automation scripts organized by platform:

### 📁 Directory Structure

```
abcloudops-scripts-kit/
├── aws/              # AWS automation scripts
│   └── check-aws-costs.sh
├── linux/            # Linux system administration scripts
├── utils/            # General utility scripts
└── README.md
```

Each directory contains platform-specific scripts with detailed documentation. Check individual script headers for usage instructions, version info, and examples.

### Available Scripts
Browse the directories above to discover available scripts. Each script includes:
- Detailed header with description and version
- Usage examples and parameters
- Prerequisites and dependencies
- Author information and contact

---

## ✅ Prerequisites

### General Requirements
- **Bash** 4.0 or higher
- **Git** (for cloning the repository)
- Platform-specific tools (check individual script headers for requirements)

---

## 🚀 Installation

### Clone the Repository

```bash
git clone https://github.com/engabelal/abcloudops-scripts-kit.git
cd abcloudops-scripts-kit
```

### Make Scripts Executable

```bash
chmod +x aws/*.sh
chmod +x linux/*.sh
chmod +x utils/*.sh
```

---

## 💻 Usage

### General Usage Pattern

**Basic Execution:**
```bash
./<platform>/<script-name>.sh
```

**With Environment Variables:**
```bash
VARIABLE=value ./<platform>/<script-name>.sh
```

**With Multiple Parameters:**
```bash
VAR1=value1 VAR2=value2 ./<platform>/<script-name>.sh
```

### Common Features

Most scripts provide:
- 📊 Color-coded console output
- 💾 Timestamped report files
- ⚙️ Environment variable configuration
- 📝 Detailed logging
- ✅ Exit status codes

### Script Documentation

Each script contains:
- Header with version and author info
- Inline comments explaining logic
- Usage examples in comments
- Configuration options

Run any script with `-h` or `--help` for detailed usage information (if supported).

---

## 🔧 Configuration

Scripts can be configured via:
- **Environment Variables** - Override defaults without editing files
- **Script Headers** - Modify configuration section in each script
- **Command-line Arguments** - Pass parameters directly (script-dependent)

### Customization Tips

- Edit configuration sections at the top of each script
- Add custom logic in designated sections
- Modify output formats as needed
- Integrate with your existing tools and workflows
- Add notifications (email, Slack, etc.)

---

## 🤝 Contributing

Contributions are welcome! Here's how:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-script`)
3. **Commit** your changes (`git commit -m 'Add amazing script'`)
4. **Push** to the branch (`git push origin feature/amazing-script`)
5. **Open** a Pull Request

### Script Guidelines
- Add comprehensive comments
- Include version number and author
- Test on multiple environments
- Update README with usage examples
- Follow existing code style

---

## 📝 Roadmap

- [ ] Azure cost optimization scripts
- [ ] Kubernetes resource management
- [ ] Multi-cloud cost comparison
- [ ] Automated cleanup with dry-run mode
- [ ] Slack/Teams notifications
- [ ] Terraform state analysis
- [ ] Docker container optimization
- [ ] CI/CD pipeline integration

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

```
MIT License

Copyright (c) 2025 Ahmed Belal

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
```

---

## 📞 Contact

- **GitHub:** [@engabelal](https://github.com/engabelal)
- **LinkedIn:** [linkedin.com/in/engabelal](https://linkedin.com/in/engabelal)
- **Email:** eng.abelal@gmail.com

---

## ⭐ Support

If you find these scripts helpful, please:
- ⭐ Star this repository
- 🐛 Report bugs via [Issues](https://github.com/engabelal/abcloudops-scripts-kit/issues)
- 💡 Suggest new features
- 📢 Share with your network

---

**Made with ❤️ by Ahmed Belal**
