use jrsonnet_evaluator::typed::BoundedI8;
use semver::{BuildMetadata, Prerelease, Version};

/// See [`crate::generator::Verdict`]'s `bump` field
#[derive(PartialEq, Eq, PartialOrd, Ord, Debug, Default, Clone, Copy)]
pub enum Bump {
    #[default]
    None,
    Patch,
    Minor,
    Major,
}
impl Bump {
    pub fn from_raw(raw: BoundedI8<0, 3>) -> Self {
        match raw.value() {
            0 => Self::None,
            1 => Self::Patch,
            2 => Self::Minor,
            3 => Self::Major,
            _ => unreachable!("raw is bounded"),
        }
    }
    pub fn apply(&self, ver: &Version) -> Version {
        if self == &Self::None {
            return ver.clone();
        }
        if ver.major == 0 {
            match self {
                Self::Major => Version {
                    major: 0,
                    minor: ver.minor + 1,
                    patch: 0,
                    pre: Prerelease::EMPTY,
                    build: BuildMetadata::EMPTY,
                },
                Self::Minor | Self::Patch => Version {
                    major: 0,
                    minor: ver.minor,
                    patch: ver.patch + 1,
                    pre: Prerelease::EMPTY,
                    build: BuildMetadata::EMPTY,
                },
                Self::None => unreachable!(),
            }
        } else {
            match self {
                Self::Major => Version {
                    major: ver.major + 1,
                    minor: 0,
                    patch: 0,
                    pre: Prerelease::EMPTY,
                    build: BuildMetadata::EMPTY,
                },
                Self::Minor => Version {
                    major: ver.major,
                    minor: ver.minor + 1,
                    patch: 0,
                    pre: Prerelease::EMPTY,
                    build: BuildMetadata::EMPTY,
                },
                Self::Patch => Version {
                    major: ver.major,
                    minor: ver.minor,
                    patch: ver.patch + 1,
                    pre: Prerelease::EMPTY,
                    build: BuildMetadata::EMPTY,
                },
                Self::None => unreachable!(),
            }
        }
    }
}
