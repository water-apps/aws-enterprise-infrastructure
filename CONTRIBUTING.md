# Contributing to AWS Enterprise Infrastructure

Thank you for your interest in contributing! This project represents enterprise DevOps patterns from 20+ years of experience in financial services and telecommunications.

## How to Contribute

### Reporting Issues

If you find a bug or have a suggestion:

1. **Check existing issues** - Someone may have already reported it
2. **Create a new issue** with:
   - Clear, descriptive title
   - Steps to reproduce (for bugs)
   - Expected vs actual behavior
   - Your environment (Terraform version, AWS region, etc.)
   - Relevant logs or error messages

### Suggesting Enhancements

We welcome suggestions for:
- Cost optimization techniques
- Security improvements
- Additional AWS services
- Documentation enhancements
- Automation improvements

Open an issue with the `enhancement` label and describe:
- The problem you're trying to solve
- Your proposed solution
- Why it benefits enterprise deployments

### Pull Requests

1. **Fork the repository**
2. **Create a feature branch** (`git checkout -b feature/amazing-feature`)
3. **Make your changes**
4. **Test thoroughly** - Deploy to a test AWS account
5. **Update documentation** - README, relevant guides
6. **Commit with clear messages** - Explain what and why
7. **Push to your fork** (`git push origin feature/amazing-feature`)
8. **Open a Pull Request**

## Code Standards

### Terraform Code

- **Follow HashiCorp style guide**
- **Use descriptive resource names** - `aws_vpc.main` not `aws_vpc.v1`
- **Add comments for complex logic**
- **Tag all resources** with Environment, Project, ManagedBy
- **Use variables** - No hardcoded values
- **Test in dev first** - Never test in production

### Documentation

- **Update README.md** if adding features
- **Add to relevant guides** (DEPLOYMENT_ORDER, COST_OPTIMIZATION, etc.)
- **Include examples** - Show usage, not just explanation
- **Keep tone professional** - This showcases enterprise expertise

### Commit Messages

Use conventional commits format:

```
feat: Add Aurora Serverless option for database
fix: Correct security group ingress rule
docs: Update cost estimates for 2025
chore: Upgrade Terraform provider to 5.x
```

## Testing

Before submitting:

1. **Run terraform fmt** - Format all .tf files
2. **Run terraform validate** - Check syntax
3. **Deploy to test account** - Verify it actually works
4. **Check costs** - Document any cost changes
5. **Test destruction** - Ensure clean teardown

## Areas for Contribution

### High Priority

- [ ] Add support for additional regions (currently Sydney-focused)
- [ ] Multi-region deployment options
- [ ] Automated security scanning (tfsec, checkov)
- [ ] Cost estimation before deployment
- [ ] Backup/restore automation scripts

### Nice to Have

- [ ] Support for additional database engines (MySQL, Aurora)
- [ ] Kubernetes (EKS) alternative to ECS
- [ ] Lambda function examples
- [ ] WAF configuration templates
- [ ] More CI/CD pipeline examples (GitLab, Bitbucket)

### Documentation

- [ ] Video walkthrough of deployment
- [ ] Architecture decision records (ADRs)
- [ ] Common troubleshooting scenarios
- [ ] Performance tuning guide
- [ ] Migration guide from other platforms

## Questions?

Open a GitHub Discussion or issue. No question is too basic.

## Code of Conduct

- **Be respectful** - Assume good intent
- **Be helpful** - Remember you were new once
- **Be constructive** - Suggest solutions, not just criticism
- **Be professional** - This represents enterprise work

## Recognition

Contributors will be acknowledged in:
- README.md contributors section
- Release notes for significant contributions

Thank you for helping improve enterprise AWS infrastructure!
