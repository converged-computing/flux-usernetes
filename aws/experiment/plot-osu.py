#!/usr/bin/env python3

import argparse
import os
import json
import time
import fnmatch

from metricsoperator.metrics.network.osu_benchmark import parse_barrier_section, parse_multi_section
import metricsoperator.utils as utils
import seaborn as sns
import matplotlib.pyplot as plt
import pandas

plt.style.use("bmh")
here = os.path.dirname(os.path.abspath(__file__))


def get_parser():
    parser = argparse.ArgumentParser(
        description="Run OSU Benchmarks Metric and Get Output",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument(
        "--results",
        help="directory with raw results data",
        default=os.path.join(here, "final", "results-osu"),
    )
    parser.add_argument(
        "--out",
        help="directory to save parsed results",
        default=os.path.join(here, "img"),
    )
    return parser



def recursive_find(base, pattern="*.*"):
    """
    Recursively find and yield files matching a glob pattern.
    """
    for root, _, filenames in os.walk(base):
        for filename in fnmatch.filter(filenames, pattern):
            yield os.path.join(root, filename)


def find_inputs(input_dir):
    """
    Find inputs (results files)
    """
    files = []
    for filename in recursive_find(input_dir, pattern="*.out"):
        # We only have data for small
        files.append(filename)
    return files


def main():
    """
    Run the main plotting operation!
    """
    parser = get_parser()
    args, _ = parser.parse_known_args()

    # Output images and data
    outdir = os.path.abspath(args.out)
    indir = os.path.abspath(args.results)
    if not os.path.exists(outdir):
        os.makedirs(outdir)

    # Find input files (skip anything with test)
    files = find_inputs(indir)
    if not files:
        raise ValueError(f"There are no input files in {indir}")

    # This does the actual parsing of data into a formatted variant
    dfs = parse_data(files)
    for key, df in dfs.items():
        df.to_csv(os.path.join(outdir, f"osu-results-{key}.csv"))
    plot_results(dfs, outdir)


def plot_results(dfs, img):
    """
    Plot result images to file
    """
    # Save each completed data frame to file and plot!
    for slug, df in dfs.items():
        print(slug)
        if slug == "latency":
            combined = df.groupby(['experiment', 'size']).mean()
            combined.to_csv(os.path.join(img, "osu-latency-only.csv"))
        if "size" in df.columns:
            print(df.groupby(['experiment','nodes', 'size']).mean())
            print(df.groupby(['experiment','nodes', 'size']).std())
        else:
            print(df.groupby(['experiment','nodes']).mean())
            print(df.groupby(['experiment','nodes']).std())
    return

    # Save each completed data frame to file and plot!
    for slug, df in dfs.items():

        # Barrier we can show across nodes
        if slug == "barrier":

            # Remove usernetes from the set
            without_usernetes = df[df.experiment != "usernetes"]

            # Separate x and y - latency (y) is a function of size (x)        
            x = "ranks"
            y = "average_latency_us"

            # for sty in plt.style.available:
            ax = sns.lineplot(
                data=df, x=x, y=y, markers=True, dashes=True, errorbar=("ci", 95), hue="experiment", palette="Set1"
            )
            plt.title(f"{slug} (y) as a function of size (x) across nodes")
            ax.set_xlabel("size (logscale)", fontsize=16)
            ax.set_ylabel("Average latency (logscale)", fontsize=16)
            ax.set_xticklabels(ax.get_xmajorticklabels(), fontsize=14)
            ax.set_yticklabels(ax.get_yticks(), fontsize=14)
            plt.subplots_adjust(left=0.2, bottom=0.2)
            plt.xscale("log")
            plt.yscale("log")
            plt.savefig(os.path.join(img, f"osu-{slug}-across-nodes.png"))
            plt.clf()
            plt.close()

            ax = sns.lineplot(
                data=without_usernetes, x=x, y=y, markers=True, dashes=True, errorbar=("ci", 95), hue="experiment", palette="Set1"
            )
            plt.title(f"{slug} (y) as a function of size (x) across nodes")
            ax.set_xlabel("size (logscale)", fontsize=16)
            ax.set_ylabel("Average latency (logscale)", fontsize=16)
            ax.set_xticklabels(ax.get_xmajorticklabels(), fontsize=14)
            ax.set_yticklabels(ax.get_yticks(), fontsize=14)
            plt.xscale("log")
            plt.yscale("log")
            plt.subplots_adjust(left=0.2, bottom=0.2)
            plt.savefig(os.path.join(img, f"osu-{slug}-across-nodes-without-usernetes.png"))
            plt.clf()
            plt.close()
            continue

        for nodes in df.nodes.unique():
            print(f"Preparing plot for {slug}")

            subset = df[df.nodes == nodes]

            # Remove usernetes from the set
            without_usernetes = df[df.experiment != "usernetes"]

            # Separate x and y - latency (y) is a function of size (x)        
            x = "size"
            if slug == "barrier":
                x = "ranks"
            y = "average_latency_us"
            
            # for sty in plt.style.available:
            ax = sns.lineplot(
                data=subset, x=x, y=y, markers=True, dashes=True, errorbar=("ci", 95), hue="experiment", palette="Set1"
            )
            plt.title(f"{slug} (y) as a function of {x} (x) on {nodes} nodes")
            ax.set_xlabel(x + " (logscale)", fontsize=16)
            ax.set_ylabel("Average latency (logscale)", fontsize=16)
            ax.set_xticklabels(ax.get_xmajorticklabels(), fontsize=14)
            ax.set_yticklabels(ax.get_yticks(), fontsize=14)
            plt.subplots_adjust(left=0.2, bottom=0.2)
            plt.xscale("log")
            plt.yscale("log")
            plt.savefig(os.path.join(img, f"osu-{slug}-{nodes}-nodes.png"))
            plt.clf()
            plt.close()

            ax = sns.lineplot(
                data=without_usernetes, x=x, y=y, markers=True, dashes=True, errorbar=("ci", 95), hue="experiment", palette="Set1"
            )
            plt.title(f"{slug} (y) as a function of {x} (x) on {nodes} nodes")
            ax.set_xlabel(x + " (logscale)", fontsize=16)
            ax.set_ylabel("Average latency (logscale)", fontsize=16)
            ax.set_xticklabels(ax.get_xmajorticklabels(), fontsize=14)
            ax.set_yticklabels(ax.get_yticks(), fontsize=14)
            plt.xscale("log")
            plt.yscale("log")
            plt.subplots_adjust(left=0.2, bottom=0.2)
            plt.savefig(os.path.join(img, f"osu-{slug}-{nodes}-nodes-without-usernetes.png"))
            plt.clf()
            plt.close()


def parse_data(files):
    """
    Given a listing of files, parse into results data frame
    """
    # Parse into data frames for type
    df_barrier = pandas.DataFrame(
        columns=[
            "ranks",
            "experiment",
            "iteration",
            "average_latency_us",
            "nodes",
        ]
    )
    barrier_idx = 0
    
    df_latency = pandas.DataFrame(
        columns=[
            "ranks",
            "experiment",
            "iteration",
            "size",
            "average_latency_us",
            "nodes",
        ]
    )
    latency_idx = 0

    df_reduce = pandas.DataFrame(
        columns=[
            "ranks",
            "experiment",
            "iteration",
            "size",
            "average_latency_us",
            "nodes",
        ]
    )
    reduce_idx = 0
    
    for filename in files:
        parsed = os.path.relpath(filename, here)
        pieces = parsed.split(os.sep)
        experiment = pieces[-2]
        filebase = pieces[-1]

        # barrier and allreduce, ranks are relevant
        if "all_reduce" in filename:
            iteration = int(filebase.split("-")[-1].replace(".out", ""))
            nodes = int(filebase.split("-")[-3])
            tasks = int(filebase.split("-")[-2])
        elif "all-reduce" in filename:
            iteration = int(filebase.split("-")[-1].replace(".out", ""))
            nodes = int(filebase.split("-")[-2])
            tasks = nodes * 16
        elif "osu_barrier" in filename:
            iteration = int(filebase.split("-")[-1].replace(".out", ""))
            nodes = int(filebase.split("-")[-3])
            tasks = int(filebase.split("-")[-2])
        elif "osu-barrier" in filename:
            iteration = int(filebase.split("-")[-1].replace(".out", ""))
            nodes = int(filebase.split("-")[-2])
            tasks = nodes * 16
        else:
            iteration = int(filebase.split("-")[-1].replace(".out", ""))
            nodes = 2
            tasks = 2

        # Save CPU line
        # This is a list, each a json result, 20x
        item = utils.read_file(filename)

        # Full command is the first item
        if "barrier" in filename:
            result = float(item.strip().split('\n')[-1].strip())
            df_barrier.loc[barrier_idx, :] = [tasks, experiment, iteration, result, nodes]
            barrier_idx +=1
            continue
        
        if "latency" in filename:
             result = parse_multi_section(item.split('\n'))
             for row in result['matrix']:
                 df_latency.loc[latency_idx, :] = [tasks, experiment, iteration, row[0], row[1], nodes]
                 latency_idx +=1
             continue

        if "reduce" in filename:
             result = parse_multi_section([x for x in item.split('\n') if x])
             for row in result['matrix']:
                 df_reduce.loc[reduce_idx, :] = [tasks, experiment, iteration, row[0], row[1], nodes]
                 reduce_idx +=1
        
    dfs = {'all_reduce': df_reduce, "latency": df_latency, "barrier": df_barrier}
    return dfs


if __name__ == "__main__":
    main()
