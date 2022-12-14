//! Types used by `--generator` code

use std::{marker::PhantomData, ops::Deref};

use jrsonnet_evaluator::{
    error::{Error, Result},
    function::native::NativeDesc,
    typed::{BoundedI8, CheckType, ComplexValType, Typed, ValType},
    State, Val,
};

// TODO: Move to jrsonnet_evaluator::typed
pub struct NativeFn<T>(PhantomData<T>, T::Value)
where
    T: NativeDesc;

impl<T> Typed for NativeFn<T>
where
    T: NativeDesc,
{
    const TYPE: &'static ComplexValType = &ComplexValType::Simple(ValType::Func);

    fn into_untyped(_typed: Self, _s: State) -> Result<Val> {
        Err(Error::RuntimeError("can't convert arbitrary function to native".into()).into())
    }

    fn from_untyped(untyped: Val, s: State) -> Result<Self> {
        Self::TYPE.check(s, &untyped)?;
        let fun = untyped.as_func().expect("type checked");
        Ok(Self(PhantomData, fun.into_native::<T>()))
    }
}
impl<T> Deref for NativeFn<T>
where
    T: NativeDesc,
{
    type Target = T::Value;

    fn deref(&self) -> &Self::Target {
        &self.1
    }
}

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

#[derive(jrsonnet_evaluator::typed::Typed)]
pub struct Generator {
    #[typed(rename = "commitHandler")]
    pub commit_handler: NativeFn<((Vec<Commit>,), Verdict)>,
}
