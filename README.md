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

### AWS Scripts

| Script | Description | Version |
|--------|-------------|---------|
| [check-aws-costs.sh](aws/check-aws-costs.sh) | Scans AWS account for billable resources (EC2, EBS, EIP, NAT, RDS, etc.) | v1.1 |

**Coming Soon:**
- `cleanup-unused-resources.sh` - Automatically remove unused AWS resources
- `backup-ec2-snapshots.sh` - Automated EBS snapshot management
- `audit-iam-users.sh` - Security audit for IAM users and permissions
- `monitor-aws-health.sh` - Real-time AWS service health monitoring

### Azure Scripts

**Coming Soon:**
- `check-azure-costs.sh` - Azure cost optimization scanner
- `cleanup-azure-resources.sh` - Remove unused Azure resources

### Kubernetes Scripts

**Coming Soon:**
- `k8s-health-check.sh` - Kubernetes cluster health monitoring
- `k8s-resource-cleanup.sh` - Clean up unused K8s resources

---

## ✅ Prerequisites

### General Requirements
- **Bash** 4.0 or higher
- **Git** (for cloning the repository)

### AWS Scripts
- **AWS CLI** v2.x installed and configured
- **AWS Credentials** configured (`~/.aws/credentials` or environment variables)
- **IAM Permissions** for the services you want to scan

### Installation Guides
- [Install AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Configure AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html)

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
chmod +x azure/*.sh
chmod +x kubernetes/*.sh
```

---

## 💻 Usage

### AWS Cost Scanner

**Basic Usage:**
```bash
./aws/check-aws-costs.sh
```

**Custom Region:**
```bash
AWS_REGION=us-east-1 ./aws/check-aws-costs.sh
```

**Custom Profile:**
```bash
AWS_PROFILE=production ./aws/check-aws-costs.sh
```

**Both Custom Region and Profile:**
```bash
AWS_REGION=eu-west-1 AWS_PROFILE=staging ./aws/check-aws-costs.sh
```

**Output:**
- Console output with color-coded warnings
- Timestamped report file: `aws-cost-report-YYYYMMDD-HHMMSS.txt`

**What It Checks:**
- ✅ Running EC2 instances
- ✅ Unattached Elastic IPs (wasting money!)
- ✅ Detached EBS volumes (still billed!)
- ✅ Lambda functions
- ✅ S3 buckets
- ✅ NAT Gateways (expensive!)
- ✅ Load Balancers (ALB/NLB)
- ✅ RDS instances

---

## 📊 Example Output

```
=
🔍 AWS Cost & Resource Scanner v1.1
Made by: Ahmed Belal | GitHub: @engabelal
Region: eu-north-1 | Profile: default
Date: 2025-01-15 14:30:00
=

💻 EC2 Instances (Running):
⚠️  Found 2 running EC2 instance(s)

🌐 Elastic IPs (Unattached - Billed!):
❌ Found 1 unattached Elastic IP(s) - WASTING MONEY!

💾 EBS Volumes (Detached - Still Billed!):
❌ Found 3 detached EBS volume(s) - WASTING MONEY!

🚦 NAT Gateways (Very Expensive!):
💸 Found 1 NAT Gateway(s) - ~$0.045/hour each!

=
📊 SUMMARY
=
Total billable resources found: 7
⚠️  WARNING: You have 7 resources that may be costing money!

💾 Report saved to: aws-cost-report-20250115-143000.txt
```

---

## 🔧 Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_REGION` | AWS region to scan | `eu-north-1` |
| `AWS_PROFILE` | AWS CLI profile to use | `default` |

### Customization

Edit the scripts to:
- Change default region/profile
- Add custom resource checks
- Modify output format
- Add email notifications
- Integrate with monitoring tools

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
