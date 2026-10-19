//! Isolated, synchronous cipher callback. QuickJS values stay on one worker thread.
//! No WebView, BotGuard context, module loader, Rust functions or host IO are exposed.

use rquickjs::{Coerced, Context, FromJs, Runtime, Value};
use sideb_core::{CipherJsRuntime, SideBCore, SideBError};
use std::sync::{mpsc, Arc};
use std::time::{Duration, Instant};

const MAX_SCRIPT_BYTES: usize = 16 * 1024 * 1024;
const MAX_EXPRESSION_BYTES: usize = 64 * 1024;
const MAX_RESULT_BYTES: usize = 64 * 1024;
const MEMORY_LIMIT: usize = 128 * 1024 * 1024;
const STACK_LIMIT: usize = 512 * 1024;
const LOAD_BUDGET: Duration = Duration::from_secs(5);
const EVALUATE_BUDGET: Duration = Duration::from_secs(1);

// Match the small browser surface used by Apple's cipher host. These are inert
// JS objects, including XHR: they cannot reach the UI, network, vault or disk.
const BROWSER_SHIMS: &str = r#"
var window=this; var self=this; var _yt_player={};
var location={href:'https://www.youtube.com/',hostname:'www.youtube.com',protocol:'https:'};
window.location=location;
var navigator={userAgent:'Mozilla/5.0'};
var document={createElement:function(){return {style:{},setAttribute:function(){},appendChild:function(){}}},
    documentElement:{appendChild:function(){}},body:{appendChild:function(){}},addEventListener:function(){}};
var XMLHttpRequest=function(){this.open=function(){};this.send=function(){};this.setRequestHeader=function(){}};
"#;

enum Request {
    Load(String, mpsc::SyncSender<bool>),
    Evaluate(String, mpsc::SyncSender<Option<String>>),
}

pub(crate) struct WindowsCipherJsRuntime {
    requests: mpsc::SyncSender<Request>,
}

impl WindowsCipherJsRuntime {
    fn new() -> Result<Self, std::io::Error> {
        // The bounded queue prevents bursts of concurrent callers retaining an
        // unbounded number of player scripts. Closing the last sender ends it.
        let (requests, receiver) = mpsc::sync_channel(8);
        std::thread::Builder::new()
            .name("sideb-cipher-js".into())
            .stack_size(2 * 1024 * 1024)
            .spawn(move || {
                let mut context = None;
                for request in receiver {
                    match request {
                        Request::Load(script, reply) => {
                            // Clear even on malformed/oversized replacement: never
                            // evaluate an old player's functions after a failed load.
                            drop(context.take());
                            context = load_context(&script, LOAD_BUDGET);
                            if context.is_none() {
                                eprintln!("[Cipher] stage=load result=failed");
                            }
                            let _ = reply.send(context.is_some());
                        }
                        Request::Evaluate(expression, reply) => {
                            let result = context.as_ref().and_then(|context| {
                                evaluate(context, &expression, EVALUATE_BUDGET)
                            });
                            if result.is_none() {
                                // Do not print the expression, script or JS exception:
                                // those may contain signed URLs or private values.
                                eprintln!("[Cipher] stage=evaluate result=failed");
                            }
                            let _ = reply.send(result);
                        }
                    }
                }
            })?;
        Ok(Self { requests })
    }
}

impl CipherJsRuntime for WindowsCipherJsRuntime {
    fn load(&self, script: String) -> bool {
        let (reply, result) = mpsc::sync_channel(1);
        self.requests.send(Request::Load(script, reply)).is_ok() && result.recv().unwrap_or(false)
    }

    fn evaluate(&self, expression: String) -> Option<String> {
        if expression.len() > MAX_EXPRESSION_BYTES {
            return None;
        }
        let (reply, result) = mpsc::sync_channel(1);
        self.requests
            .send(Request::Evaluate(expression, reply))
            .ok()?;
        result.recv().ok().flatten()
    }
}

fn set_deadline(runtime: &Runtime, budget: Duration) {
    let deadline = Instant::now() + budget;
    runtime.set_interrupt_handler(Some(Box::new(move || Instant::now() >= deadline)));
}

fn load_context(script: &str, budget: Duration) -> Option<Context> {
    if script.len() > MAX_SCRIPT_BYTES {
        return None;
    }
    let runtime = Runtime::new().ok()?;
    runtime.set_memory_limit(MEMORY_LIMIT);
    runtime.set_max_stack_size(STACK_LIMIT);
    set_deadline(&runtime, budget);
    let context = Context::full(&runtime).ok()?;
    let loaded = context.with(|ctx| {
        ctx.eval::<(), _>(BROWSER_SHIMS)?;
        ctx.eval::<(), _>(script)?;
        ctx.eval::<String, _>("typeof window._cipherSigFunc")
    });
    match loaded.as_deref() {
        Ok("function") => Some(context),
        _ => None,
    }
}

fn evaluate(context: &Context, expression: &str, budget: Duration) -> Option<String> {
    set_deadline(context.runtime(), budget);
    context.with(|ctx| {
        let value: Value = ctx.eval(expression).ok()?;
        if value.is_null() || value.is_undefined() {
            return None;
        }
        let value = Coerced::<String>::from_js(&ctx, value).ok()?.0;
        (value.len() <= MAX_RESULT_BYTES).then_some(value)
    })
}

/// Both startup and retry must use this factory, before publishing the core or
/// restoring a session. The runtime does not depend on an account being present.
pub(crate) fn create_core(data_dir: String) -> Result<Arc<SideBCore>, SideBError> {
    let runtime = WindowsCipherJsRuntime::new().map_err(|_| SideBError::Other {
        message: "No se pudo inicializar el runtime de audio.".into(),
    })?;
    let core = SideBCore::new_windows(data_dir)?;
    core.set_cipher_js_runtime(Box::new(runtime));
    Ok(core)
}

/// Only emit a finite category, never the core's free-form error message.
/// AllClientsFailed does not identify which client/cipher/auth check failed.
pub(crate) fn resolution_failure_category(error: &SideBError) -> &'static str {
    match error {
        SideBError::NetworkError { .. } => "network",
        SideBError::ParseError { .. } => "parse",
        SideBError::StreamError { message }
            if message.starts_with("this upload could not be played.") =>
        {
            "upload_unavailable"
        }
        SideBError::StreamError { message }
            if message.starts_with("no client could resolve a playable stream for ") =>
        {
            "all_clients_failed"
        }
        SideBError::StreamError { .. } => "stream",
        SideBError::DbError { .. } => "storage",
        SideBError::NotFound { .. } => "not_found",
        SideBError::Other { .. } => "other",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PLAYER: &str = r#"
        window._cipherSigFunc = function(s) { return s.split('').reverse().join(''); };
        window._nTransformFunc = function(n) { return 'n:' + n.slice(1); };
    "#;

    #[test]
    fn cipher_loads_and_evaluates_signature_n_and_escaped_input() {
        let runtime = WindowsCipherJsRuntime::new().unwrap();
        assert_eq!(runtime.evaluate("'before load'".into()), None);
        assert!(runtime.load(PLAYER.into()));
        assert_eq!(
            runtime
                .evaluate("typeof window._cipherSigFunc".into())
                .as_deref(),
            Some("function")
        );
        let input = "a'\"\\&/ñ";
        assert_eq!(
            runtime.evaluate(format!(
                "window._cipherSigFunc({})",
                serde_json::to_string(input).unwrap()
            )),
            Some(input.chars().rev().collect())
        );
        assert_eq!(
            runtime
                .evaluate("window._nTransformFunc('abc')".into())
                .as_deref(),
            Some("n:bc")
        );
    }

    #[test]
    fn cipher_replaces_context_and_failed_load_clears_previous_functions() {
        let runtime = WindowsCipherJsRuntime::new().unwrap();
        assert!(runtime.load(format!("{PLAYER}; window.previous='private';")));
        assert!(runtime.load("window._cipherSigFunc=function(s){return 'new:'+s}".into()));
        assert_eq!(
            runtime.evaluate("typeof window.previous".into()).as_deref(),
            Some("undefined")
        );
        assert_eq!(
            runtime
                .evaluate("window._cipherSigFunc('x')".into())
                .as_deref(),
            Some("new:x")
        );
        for invalid in [
            "var broken = ;",
            "window._cipherSigFunc = 42",
            "throw new Error('secret')",
        ] {
            assert!(!runtime.load(invalid.into()));
            assert_eq!(runtime.evaluate("window._cipherSigFunc('x')".into()), None);
        }
        assert!(runtime.load(PLAYER.into()));
        assert_eq!(
            runtime
                .evaluate("window._cipherSigFunc('abc')".into())
                .as_deref(),
            Some("cba")
        );
    }

    #[test]
    fn cipher_errors_and_empty_results_allow_the_core_to_fallback() {
        let runtime = WindowsCipherJsRuntime::new().unwrap();
        assert!(runtime.load(PLAYER.into()));
        for expression in [
            "undefined",
            "null",
            "unknown()",
            "(() => {throw new Error('private')})()",
        ] {
            assert_eq!(runtime.evaluate(expression.into()), None);
        }
        assert_eq!(runtime.evaluate("''".into()), Some(String::new()));
        assert_eq!(runtime.evaluate("123".into()).as_deref(), Some("123"));
        assert_eq!(
            runtime
                .evaluate("window._cipherSigFunc('abc')".into())
                .as_deref(),
            Some("cba")
        );
    }

    #[test]
    fn cipher_exposes_no_host_bridges_or_module_loader() {
        let runtime = WindowsCipherJsRuntime::new().unwrap();
        assert!(runtime.load(PLAYER.into()));
        assert_eq!(runtime.evaluate("[typeof fetch,typeof require,typeof process,typeof Deno,typeof std,typeof os,typeof __TAURI__,typeof localStorage,typeof document.cookie].join(',')".into()).as_deref(), Some("undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined"));
        assert_eq!(
            runtime.evaluate("new XMLHttpRequest().send('secret')".into()),
            None
        );
    }

    #[test]
    fn cipher_serializes_concurrent_calls_and_keeps_instances_separate() {
        let runtime = Arc::new(WindowsCipherJsRuntime::new().unwrap());
        let other = WindowsCipherJsRuntime::new().unwrap();
        assert!(runtime.load(format!("{PLAYER}; var counter=0;")));
        assert!(other.load(PLAYER.into()));
        let workers: Vec<_> = (0..16)
            .map(|_| {
                let runtime = runtime.clone();
                std::thread::spawn(move || {
                    runtime
                        .evaluate("++counter".into())
                        .unwrap()
                        .parse::<u32>()
                        .unwrap()
                })
            })
            .collect();
        let mut values: Vec<_> = workers
            .into_iter()
            .map(|worker| worker.join().unwrap())
            .collect();
        values.sort_unstable();
        assert_eq!(values, (1..=16).collect::<Vec<_>>());
        assert_eq!(
            other.evaluate("typeof counter".into()).as_deref(),
            Some("undefined")
        );
    }

    #[test]
    fn cipher_interrupts_unbounded_code_and_accepts_a_fresh_context() {
        let budget = Duration::from_millis(20);
        assert!(load_context("while(true){}", budget).is_none());
        let context = load_context(PLAYER, LOAD_BUDGET).unwrap();
        assert_eq!(evaluate(&context, "while(true){}", budget), None);
        assert_eq!(
            evaluate(&context, "(() => {while(true){}})()", budget),
            None
        );
        assert_eq!(
            evaluate(&context, "window._cipherSigFunc('abc')", EVALUATE_BUDGET).as_deref(),
            Some("cba")
        );
    }

    #[test]
    fn cipher_bounds_inputs_and_results_and_recovers_after_oversized_load() {
        let runtime = WindowsCipherJsRuntime::new().unwrap();
        assert!(runtime.load(PLAYER.into()));
        assert_eq!(runtime.evaluate(" ".repeat(MAX_EXPRESSION_BYTES + 1)), None);
        assert_eq!(
            runtime.evaluate(format!("'x'.repeat({})", MAX_RESULT_BYTES + 1)),
            None
        );
        assert!(!runtime.load(" ".repeat(MAX_SCRIPT_BYTES + 1)));
        assert_eq!(
            runtime.evaluate("window._cipherSigFunc('abc')".into()),
            None
        );
        assert!(runtime.load(PLAYER.into()));
    }

    #[test]
    fn cipher_bounds_memory_and_recursion_without_losing_the_worker() {
        let runtime = WindowsCipherJsRuntime::new().unwrap();
        assert!(runtime.load(PLAYER.into()));
        assert_eq!(
            runtime.evaluate("new ArrayBuffer(256 * 1024 * 1024)".into()),
            None
        );
        assert_eq!(
            runtime.evaluate("(function recurse(){return recurse()})()".into()),
            None
        );
        assert!(runtime.load(PLAYER.into()));
        assert_eq!(
            runtime
                .evaluate("window._cipherSigFunc('abc')".into())
                .as_deref(),
            Some("cba")
        );
    }

    #[test]
    fn resolution_diagnostics_do_not_retain_free_form_messages() {
        let secret = "https://private.invalid/?signature=secret cookie=secret";
        assert_eq!(
            resolution_failure_category(&SideBError::NetworkError {
                message: secret.into()
            }),
            "network"
        );
        assert_eq!(
            resolution_failure_category(&SideBError::StreamError {
                message: format!("no client could resolve a playable stream for {secret}")
            }),
            "all_clients_failed"
        );
        assert_eq!(
            resolution_failure_category(&SideBError::StreamError {
                message: secret.into()
            }),
            "stream"
        );
    }

    #[test]
    fn startup_and_retry_use_the_factory_that_registers_the_cipher() {
        let host = include_str!("lib.rs");
        assert_eq!(
            host.matches("cipher_runtime::create_core(data_dir_str)")
                .count(),
            2
        );
        assert!(!host.contains("SideBCore::new_windows("));
    }
}
