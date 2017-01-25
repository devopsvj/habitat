
#[macro_use]
extern crate log;
extern crate env_logger;
extern crate time;
extern crate petgraph;
extern crate walkdir;
extern crate habitat_core as hab_core;
extern crate habitat_builder_protocol as protocol;
extern crate clap;

pub mod rdeps;
pub mod spider;

use clap::{Arg, App};
use spider::{Spider, SearchErr};
use std::io;
use time::PreciseTime;
use std::io::Write;

fn main() {
    env_logger::init().unwrap();

    let matches = App::new("hab-spider")
        .version("0.1.0")
        .about("Habitat package graph builder")
        .arg(Arg::with_name("PATH")
            .help("The path to the packages root")
            .required(true)
            .index(1))
        .get_matches();

    let path = matches.value_of("PATH").unwrap();

    println!("Crawling packages... please wait.");

    let mut spider = Spider::new(&path);
    let start_time = PreciseTime::now();
    let (ncount, ecount) = spider.crawl();
    let end_time = PreciseTime::now();

    println!("OK: {} nodes, {} edges ({} sec)",
             ncount,
             ecount,
             start_time.to(end_time));

    println!("\nAvailable commands: HELP, STATS, TOP, FIND, RDEPS, EXIT\n");

    let mut done = false;
    while !done {
        print!("spider> ");
        io::stdout().flush().ok().expect("Could not flush stdout");

        let mut cmd = String::new();
        io::stdin().read_line(&mut cmd).unwrap();

        let v: Vec<&str> = cmd.trim_right().split_whitespace().collect();

        if v.len() > 0 {
            match v[0].to_lowercase().as_str() {
                "help" => do_help(),
                "stats" => do_stats(&spider),
                "top" => {
                    let count = if v.len() < 2 {
                        10
                    } else {
                        v[1].parse::<usize>().unwrap()
                    };
                    do_top(&spider, count);
                }
                "find" => {
                    if v.len() < 2 {
                        println!("Missing search term\n")
                    } else {
                        do_find(&spider, v[1].to_lowercase().as_str())
                    }
                }
                "rdeps" => {
                    if v.len() < 2 {
                        println!("Missing package name\n")
                    } else {
                        do_rdeps(&spider, v[1].to_lowercase().as_str())
                    }
                }
                "exit" => done = true,
                _ => println!("Unknown command\n"),
            }
        }
    }
}

fn do_help() {
    println!("HELP           - print this message");
    println!("STATS          - print graph statistics");
    println!("TOP [<count>]  - print nodes with the most reverse dependencies");
    println!("FIND  <term>   - find packages that match the search term");
    println!("RDEPS <name>   - print the reverse dependencies for the package");
    println!("EXIT           - exit the application\n");
}

fn do_stats(spider: &Spider) {
    let stats = spider.stats();

    println!("Node count: {}", stats.node_count);
    println!("Edge count: {}", stats.edge_count);
    println!("Connected components: {}", stats.connected_comp);
    println!("Is cyclic: {}\n", stats.is_cyclic);
}

fn do_top(spider: &Spider, count: usize) {
    let start_time = PreciseTime::now();
    let top = spider.top(count);
    let end_time = PreciseTime::now();

    println!("OK: {} items ({} sec)\n",
             top.len(),
             start_time.to(end_time));

    for (name, count) in top {
        println!("{}: {}", name, count);
    }
    println!("");
}

fn do_find(spider: &Spider, phrase: &str) {
    let start_time = PreciseTime::now();

    match spider.search(phrase) {
        Ok(v) => {
            let end_time = PreciseTime::now();
            println!("OK: {} items ({} sec)\n", v.len(), start_time.to(end_time));

            for s in v {
                println!("{}", s);
            }
        }
        Err(SearchErr::NoResults) => println!("No matching packages found"),
        Err(SearchErr::TooManyResults) => {
            println!("Too many matching results - try a more focused search")
        }
    }
    println!("");
}

fn do_rdeps(spider: &Spider, name: &str) {
    let start_time = PreciseTime::now();

    match spider.rdeps(name) {
        Some(rdeps) => {
            let end_time = PreciseTime::now();
            println!("OK: {} items ({} sec)\n",
                     rdeps.len(),
                     start_time.to(end_time));

            for s in rdeps {
                println!("{}", s);
            }
        }
        None => println!("No entries found"),
    }

    println!("");
}
