<!-- markdownlint-disable first-line-h1 no-inline-html -->

<img src=".github/icon-400px.svg" alt="A PowerShell Module for Cloud Foundation Power Management" width="150"></br></br>

# PowerShell Module for VMware Cloud Foundation Power Management

[![Documentation](https://img.shields.io/badge/Read-Documentation-blue?logo=readthedocs)][docs-module]
[![PS Version](https://img.shields.io/powershellgallery/v/VMware.CloudFoundation.PowerManagement?label=Version)](https://www.powershellgallery.com/packages/VMware.CloudFoundation.PowerManagement)
[![PS Downloads](https://img.shields.io/powershellgallery/dt/VMware.CloudFoundation.PowerManagement?label=Downloads)](https://www.powershellgallery.com/packages/VMware.CloudFoundation.PowerManagement)
[![GitHub Clones](https://img.shields.io/badge/dynamic/json?color=success&label=Clone&query=count&url=https://gist.githubusercontent.com/nathanthaler/5743b25f01a8ef1873793d18e58862b1/raw/clone.json&logo=github)](https://gist.githubusercontent.com/nathanthaler/5743b25f01a8ef1873793d18e58862b1/raw/clone.json)

## Overview

`VMware.CloudFoundation.PowerManagement` is a PowerShell module that supports the ability to automate the shut
down and start up of the [VMware Cloud Foundation][docs-vmware-cloud-foundation] management domain or workload
domains using a PowerShell script.

The scripts follow the order for manual shutdown and startup of VMware Cloud Foundation. You can complete the
workflow manually at any point. You can also run the scripts multiple times.

For details on specific VMware Cloud Foundation versions supported by this module, please refer to the [documentation][docs-module].

## Documentation

For detailed instructions on using this module, refer to the [documentation][docs-module].

## Contributing

We encourage community contributions! To get started, please refer to the [contribution guidelines][contributing].

## Support

This module is community-driven and maintained by the project contributors. It is not officially
supported by Broadcom Support but thrives on collaboration and input from its users.

Use the GitHub [issues][gh-issues] to report bugs or suggest features and enhancements. Issues are
monitored by the maintainers and are prioritized based on criticality and community [reactions][gh-reactions].

Before filing an issue, please search the issues and use the reactions feature to add votes to
matching issues. Please include as much information as you can. Details like these are incredibly
useful in helping the us evaluate and prioritize any changes:

- A reproducible test case or series of steps.
- Any modifications you've made relevant to the bug.
- Anything unusual about your environment or deployment.

You can also start a discussion on the GitHub [discussions][gh-discussions] area to ask questions or
share ideas.

## License

© Broadcom. All Rights Reserved.

The term “Broadcom” refers to Broadcom Inc. and/or its subsidiaries.

This project is licensed under the [BSD 2-Clause License](LICENSE).

[changelog]: CHANGELOG.md
[contributing]: CONTRIBUTING.md
[docs-module]: https://vmware.github.io/powershell-module-for-vmware-cloud-foundation-power-management
[docs-vmware-cloud-foundation]: https://docs.vmware.com/en/VMware-Cloud-Foundation
[gh-discussions]: https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/discussions
[gh-issues]: https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/issues
[gh-reactions]: https://github.blog/2016-03-10-add-reactions-to-pull-requests-issues-and-comments/
[psgallery-module]: https://www.powershellgallery.com/packages/VMware.CloudFoundation.PowerManagement
