#!/usr/bin/env python3

import argparse
import collections
import fnmatch
import os

from datetime import datetime
import matplotlib.pyplot as plt
import metricsoperator.utils as utils
import pandas
import seaborn as sns

plt.style.use("bmh")
here = os.path.dirname(os.path.abspath(__file__))


def get_parser():
    parser = argparse.ArgumentParser(
        description="Plot MNist Timestamps",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument(
        "--results",
        help="directory with raw results data",
        default=os.path.join(here, "results", "flux-operator-vs-bare-metal"),
    )
    parser.add_argument(
        "--out",
        help="directory to save parsed results",
        default=os.path.join(here, "img", "flux-operator-vs-bare-metal"),
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

    df = parse_data(files)
    df.to_csv(os.path.join(outdir, "mnist-times.csv"))
    plot_results(df, outdir)

    # Show means grouped by experiment to sanity check plots
    print(df.groupby("experiment").mean())
    print(df.groupby("experiment").std())


def timestamp_to_datetime(ts):
    """
    Format: 2023-12-23T22:18:22Z
    """
    ts = ts.split("T")[-1].replace("Z", "")
    return datetime.strptime(ts, "%H:%M:%S")


def parse_mnist(item):
    """
    Parse raw text into named timestamps
    """
    lines = item.split("\n")

    # We just need to parse the real time line
    # This is only one epoch, so no splitting into epochs
    real_line = [x for x in lines if x.startswith("real")][0]
    timestamp = real_line.split("\t")[-1]

    # This is hard coded to not expect hours, we only go up to about 25 min
    minutes, rest = timestamp.split("m", 1)
    seconds = rest.replace("s", "")

    # Return time in total seconds
    return int(minutes) * 60 + float(seconds)


def plot_results(df, outdir):
    """
    Plot results
    """
    # Plot each!
    colors = sns.color_palette("hls", 16)
    hexcolors = colors.as_hex()
    types = list(df.experiment.unique())
    types.sort()

    palette = collections.OrderedDict()
    for t in types:
        palette[t] = hexcolors.pop(0)

    # First look at total times
    make_plot(
        df,
        title="Total Times of MNist Between Bare Metal and Usernetes",
        tag="mnist",
        ydimension="time_seconds",
        xdimension="experiment",
        palette=palette,
        outdir=outdir,
        ext="png",
        plotname="total_time_mnist",
        hue="experiment",
        xlabel="",
        ylabel="Time (seconds)",
    )


def parse_data(files):
    """
    Given a listing of files, parse into results data frame
    """
    # Parse into data frame (time is in seconds)
    df = pandas.DataFrame(columns=["experiment", "iteration", "time_seconds"])
    idx = 0

    for filename in files:
        parsed = os.path.relpath(filename, here)
        pieces = parsed.split(os.sep)
        experiment = pieces[-2]

        # This was me being stupid - one experiment is N-mnist.out,
        # and the other is mnist-N.out. Doh.
        try:
            iteration = int(pieces[-1].split("-")[0].replace(".out", ""))
        except:
            iteration = int(pieces[-1].split("-")[-1].replace(".out", ""))

        # Raw result file, we will need the first and last timestamp
        # We can actually try to split into different pieces of analysis (e.g., epocs) too.
        item = utils.read_file(filename)
        try:
            seconds = parse_mnist(item)
        except:
            print(f"Issue parsing {filename}, likely still running.")
            continue

        df.loc[idx, :] = [experiment, iteration, seconds]
        idx += 1

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
    hue="experiment",
    outdir="img",
):
    """
    Helper function to make common plots.
    """
    plotfunc = sns.boxplot
    # plotfunc = sns.scatterplot

    ext = ext.strip(".")
    plt.figure(figsize=(12, 12))
    sns.set_style("dark")
    ax = plotfunc(
        x=xdimension, y=ydimension, hue=hue, data=df, whis=[5, 95], palette=palette
    )
    # ax = plotfunc(x=xdimension, y=ydimension, hue=hue, data=df, palette=palette)
    plt.title(title)
    ax.set_xlabel(xlabel, fontsize=16)
    ax.set_ylabel(ylabel, fontsize=16)
    ax.set_xticklabels(ax.get_xmajorticklabels(), fontsize=14)
    ax.set_yticklabels(ax.get_yticks(), fontsize=14)
    plt.savefig(os.path.join(outdir, f"{tag}_{plotname}.{ext}"))
    plt.clf()


if __name__ == "__main__":
    main()
