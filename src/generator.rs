//! Types used by `--generator` code

use std::fmt::Debug;

use jrsonnet_evaluator::typed::{BoundedI8, NativeFn};

/// Generator input is [`Vec<Commit>`]
#[derive(jrsonnet_evaluator::typed::Typed, Debug, Clone)]
pub struct Commit {
    pub id: String,
    pub message: String,
    #[typed(rename = "authorName")]
    pub author_name: String,
    #[typed(rename = "authorEmail")]
    pub author_email: String,
}

/// Generator output
#[derive(jrsonnet_evaluator::typed::Typed)]
pub struct Verdict {
    /// Markdown formatted changelog
    pub changelog: String,
    /// 0 - no bump required, however we can still have changelog
    ///     useable for `ci:` or `style:` changes.
    /// 1 - patch bump is required.
    /// 2 - minor bump is required. If crate has zero major
    ///     version - then patch version will be bumped instead.
    /// 3 - major bump. If previous version of crate had zero major
    ///     version - then minor version will be bumped, real major
    ///     bump (release) require manual intervention instead
    // TODO: impl Typed for Bump
    pub bump: BoundedI8<0, 3>,
}
impl Debug for Verdict {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Verdict")
            .field("changelog", &self.changelog)
            .field("bump", &self.bump.value())
            .finish()
    }
}

#[derive(jrsonnet_evaluator::typed::Typed)]
pub struct Generator {
    #[typed(rename = "commitHandler")]
    pub commit_handler: NativeFn<((Vec<Commit>,), Verdict)>,
}
