#!/usr/bin/env python3

import argparse
import collections
import fnmatch
import os

from collections import OrderedDict
import matplotlib.pyplot as plt
import metricsoperator.utils as utils
import pandas
import seaborn as sns
from metricsoperator.metrics.app.lammps import parse_lammps

plt.style.use("bmh")
here = os.path.dirname(os.path.abspath(__file__))


def get_parser():
    parser = argparse.ArgumentParser(
        description="Plot LAMMPS Raw Files",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument(
        "--results",
        help="directory with raw results data",
        default=os.path.join(here, "final", "results-lammps"),
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
    # Has keys results, iters, and columns
    df = parse_data(files)

    # Show means grouped by experiment to sanity check plots
    print(df.groupby(["experiment", "nodes"]).mean())
    print(df.groupby(["experiment", "nodes"]).std())
    df.to_csv(os.path.join(outdir, "lammps-times.csv"))
    plot_results(df, outdir)


def plot_results(df, outdir):
    """
    Plot lammps results
    """
    # Ensure types are close together
    # order = ["bare-metal-with-usernetes", "bare-metal", "container", "container-with-usernetes", "usernetes"]
    # subset = df[df.experiment.isin(order)]

    # Plot each!
    colors = sns.color_palette("hls", 16)
    hexcolors = colors.as_hex()
    types = list(df.nodes.unique())
    types.sort()

    # ALWAYS double check this ordering, this
    # is almost always wrong and the colors are messed up
    palette = collections.OrderedDict()
    for t in types:
        palette[t] = hexcolors.pop(0)

    make_plot(
        df,
        title="LAMMPS Times (16 x 16 x 8) Across HPC/Usernetes Setups and Scale",
        tag="lammps",
        ydimension="time_seconds",
        xdimension="experiment",
        palette=palette,
        outdir=outdir,
        ext="png",
        plotname="lammps",
        hue="nodes",
        plot_type="bar",
        xlabel="",
        ylabel="Time (seconds)",
    )

    make_plot(
        df,
        title="LAMMPS CPU Percentage Utilization Across HPC/Usernetes Setups",
        tag="lammps-cpu-utilization",
        ydimension="percent_cpu_utilization",
        xdimension="experiment",
        palette=palette,
        outdir=outdir,
        ext="png",
        plotname="lammps-cpu-utilization",
        hue="nodes",
        plot_type="bar",
        xlabel="",
        ylabel="% CPU Utilization",
    )

    colors = sns.color_palette("hls", 16)
    hexcolors = colors.as_hex()
    types = list(df.experiment.unique())
    types.sort()

    # ALWAYS double check this ordering, this
    # is almost always wrong and the colors are messed up
    palette = collections.OrderedDict()
    for t in types:
        palette[t] = hexcolors.pop(0)

    make_plot(
        df,
        title="LAMMPS Times (16 x 16 x 8) Across HPC/Usernetes Setups and Scale",
        tag="lammps-by-ranks",
        ydimension="time_seconds",
        xdimension="ranks",
        palette=palette,
        outdir=outdir,
        ext="png",
        plotname="lammps-by-ranks",
        hue="experiment",
        plot_type="bar",
        xlabel="MPI Ranks",
        ylabel="Time (seconds)",
    )

    make_plot(
        df,
        title="LAMMPS Times (16 x 16 x 8) Across HPC/Usernetes Setups and Scale",
        tag="lammps-by-nodes",
        ydimension="time_seconds",
        xdimension="nodes",
        palette=palette,
        outdir=outdir,
        ext="png",
        plotname="lammps-by-nodes",
        hue="experiment",
        plot_type="bar",
        xlabel="Nodes",
        ylabel="Time (seconds)",
    )
    make_plot(
        df,
        title="LAMMPS Times (16 x 16 x 8) Across HPC Setups and Scale",
        tag="lammps-by-nodes-violin",
        ydimension="time_seconds",
        xdimension="nodes",
        palette=palette,
        outdir=outdir,
        ext="png",
        plotname="lammps-by-nodes-violin-hpc",
        hue="experiment",
        plot_type="bar",
        xlabel="Nodes",
        ylabel="Time (seconds)",
    )

    # Separate the above into two plots:
    # 1. everything without usernetes
    # 2. usernetes vs. everything else together
    subset = df[df.experiment != "usernetes"]
    make_plot(
        subset,
        title="LAMMPS Times (16 x 16 x 8) Across HPC Setups and Scale",
        tag="lammps-by-nodes-hpc",
        ydimension="time_seconds",
        xdimension="nodes",
        palette=palette,
        outdir=outdir,
        ext="png",
        plotname="lammps-by-nodes-hpc",
        hue="experiment",
        plot_type="bar",
        xlabel="Nodes",
        ylabel="Time (seconds)",
    )

    # Now combine all usernetes vs hpc
    subset.experiment = "hpc"
    combined = pandas.concat([subset, df[df.experiment == "usernetes"]])

    palette = OrderedDict()
    palette["hpc"] = "#e48522"
    palette["usernetes"] = "#2480ec"

    make_plot(
        combined,
        title="LAMMPS Times (16 x 16 x 8) HPC vs Usernetes Across Sizes",
        tag="lammps-by-nodes-hpc-vs-usernetes",
        ydimension="time_seconds",
        xdimension="nodes",
        palette=palette,
        outdir=outdir,
        ext="png",
        plotname="lammps-by-nodes-hpc-vs-usernetes",
        hue="experiment",
        plot_type="box",
        xlabel="Nodes",
        ylabel="Time (seconds)",
    )

    # Now JUST usernetes vs bare metal (for paper)
    subset = df[df.experiment.isin(["usernetes", "bare-metal"])]

    palette = OrderedDict()
    palette["bare-metal"] = "#e48522"
    palette["usernetes"] = "#2480ec"

    make_plot(
        subset,
        title="LAMMPS Times (16 x 16 x 8) Bare-Metal vs Usernetes Across Sizes",
        tag="bare-metal-vs-usernetes",
        ydimension="time_seconds",
        xdimension="nodes",
        palette=palette,
        outdir=outdir,
        ext="png",
        plotname="lammps-by-nodes",
        hue="experiment",
        plot_type="box",
        xlabel="Nodes",
        ylabel="Time (seconds)",
    )

    import IPython

    IPython.embed()


def parse_data(files):
    """
    Given a listing of files, parse into results data frame
    """
    # Parse into data frame
    df = pandas.DataFrame(
        columns=[
            "ranks",
            "experiment",
            "iteration",
            "time_seconds",
            "nodes",
            "percent_cpu_utilization",
        ]
    )
    idx = 0

    for filename in files:
        parsed = os.path.relpath(filename, here)
        pieces = parsed.split(os.sep)
        experiment = pieces[-2]
        filebase = pieces[-1]
        iteration = int(filebase.split("-")[-1].replace(".out", ""))
        nodes = int(filebase.split("-")[-3])

        # Save CPU line
        # This is a list, each a json result, 20x
        item = utils.read_file(filename)
        line = [x for x in item.split("\n") if "CPU use" in x]
        percent_cpu_usage = float(line[0].split(" ")[0].replace("%", ""))

        # Full command is the first item
        result = parse_lammps(item)

        # We just care about total wall time
        seconds = result["total_wall_time_seconds"]
        ranks = result["ranks"]
        df.loc[idx, :] = [
            int(ranks),
            experiment,
            iteration,
            seconds,
            int(nodes),
            percent_cpu_usage,
        ]
        idx += 1
    df.ranks = df.ranks.astype(int)
    df.nodes = df.nodes.astype(int)
    return df


def make_plot(
    df,
    title,
    tag,
    ydimension,
    xdimension,
    palette,
    xlabel,
    ylabel,
    ext="pdf",
    plotname="lammps",
    plot_type="violin",
    hue="experiment",
    outdir="img",
):
    """
    Helper function to make common plots.
    """
    plotfunc = sns.boxplot
    if plot_type == "violin":
        plotfunc = sns.violinplot

    ext = ext.strip(".")
    plt.figure(figsize=(12, 8))
    sns.set_style("dark")
    if plot_type == "violin":
        ax = plotfunc(
            x=xdimension, y=ydimension, hue=hue, data=df, linewidth=0.8, palette=palette
        )
    else:
        ax = plotfunc(
            x=xdimension,
            y=ydimension,
            hue=hue,
            data=df,
            linewidth=0.8,
            palette=palette,
            whis=[5, 95],
        )

    plt.title(title)
    ax.set_xlabel(xlabel, fontsize=16)
    ax.set_ylabel(ylabel, fontsize=16)
    ax.set_xticklabels(ax.get_xmajorticklabels(), fontsize=14)
    ax.set_yticklabels(ax.get_yticks(), fontsize=14)
    plt.savefig(os.path.join(outdir, f"{tag}_{plotname}.{ext}"))
    plt.clf()


if __name__ == "__main__":
    main()
