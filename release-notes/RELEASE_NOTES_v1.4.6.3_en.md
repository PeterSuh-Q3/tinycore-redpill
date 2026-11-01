# alpine-redpill v1.4.6.3

## Better safeguards for older CPUs

Some older x86 systems can fail before reaching the loader menu when a saved module-pack choice requires CPU instructions the processor does not support. On a confirmed BMI2 mismatch, the menu now switches that choice to an available compatible custom-module mode before displaying the menu; it does not change the selected DSM model or version.

Loader builds also include an advisory inspection of selected files in the completed DSM initrd, and the image workflows inspect the GRUB files in the final Alpine and xTCRP images. The report distinguishes detected instruction patterns from confirmed runtime failures and is shown at the end of the build log, helping identify compatibility risks before writing or booting an image.

These checks are static/advisory and do not prove that every component will run on a target CPU. They do not block a build, and affected hardware should still be used to verify boot behavior.
