// Copyright (c) 2017 Chef Software Inc. and/or applicable contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

use env_logger;
use habitat_core as core;
use habitat_launcher as launcher;
#[macro_use]
extern crate log;

use std::env;
use std::process;

use crate::launcher::server;

fn main() {
    env_logger::init();

    let args: Vec<String> = env::args().skip(1).collect();
    set_global_logging_options(&args);

    match server::run(args) {
        Err(err) => {
            error!("Launcher exiting with 1 due to err: {}", err);
            process::exit(1);
        }
        Ok(code) => {
            error!("Launcher exiting with code {}", code);
            process::exit(code);
        }
    }
}

/// In order to ensure that log output from the Launcher itself
/// behaves the same as the Supervisor, we'll eavesdrop on the
/// arguments being passed to the Supervisor in order to configure
/// ourselves.
fn set_global_logging_options(args: &[String]) {
    // Yeah, this is pretty weird, but it comes out of how the
    // hab-launch, hab, and hab-sup binaries interact.
    //
    // These flags are defined with CLAP on `hab`, so they can be
    // passed through `hab-launch` (and intercepted here), before
    // being passed on to `hab-sup`, where they are _also_ defined.
    //
    // What a tangled web we weave!

    // Note that each of these options has only one form, so we don't
    // have to check for long _and_ short options, for example.
    if args.contains(&String::from("--no-color")) {
        core::output::set_no_color(true);
    }
    if args.contains(&String::from("--json-logging")) {
        core::output::set_json(true);
    }
    if args.contains(&String::from("-v")) {
        core::output::set_verbose(true);
    }
}
