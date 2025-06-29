#!/usr/bin/env python3

import pandas
import argparse
import os
import re
import sys

from matplotlib.font_manager import FontProperties
import matplotlib.pylab as plt
import seaborn as sns
from metricsoperator.metrics.network.osu_benchmark import parse_multi_section

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)

import performance_study as ps

sns.set_theme(style="whitegrid", palette="muted")


def get_parser():
    parser = argparse.ArgumentParser(
        description="Run analysis",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument(
        "--root",
        help="root directory with experiments",
        default=os.path.join(here, "experiments"),
    )
    parser.add_argument(
        "--out",
        help="directory to save parsed results",
        default=os.path.join(here, "data"),
    )
    return parser


def main():
    """
    Find application result files to parse.
    """
    parser = get_parser()
    args, _ = parser.parse_known_args()

    # Output images and data
    outdir = os.path.abspath(args.out)
    indir = os.path.abspath(args.root)
    if not os.path.exists(outdir):
        os.makedirs(outdir)

    osu_files = list(ps.recursive_find_files(os.path.join(indir, "osu"), ".out"))
    lammps_files = list(ps.recursive_find_files(os.path.join(indir, "lammps"), ".out"))

    # Saves raw data to file
    parse_and_plot_lammps(indir, outdir, lammps_files)
    parse_and_plot_osu(indir, outdir, osu_files)


def parse_matom_steps(item):
    """
    Parse matom steps

    We separated this into a function because cyclecloud submits have
    two problem sizes in one file.
    """
    # Add in Matom steps - what is considered the LAMMPS FOM
    # https://asc.llnl.gov/sites/asc/files/2020-09/CORAL2_Benchmark_Summary_LAMMPS.pdf
    # Not parsed by metrics operator so we find the line here
    line = [x for x in item.split("\n") if "Matom-step/s" in x][0]
    return float(line.split(",")[-1].strip().split(" ")[0])


def parse_and_plot_lammps(indir, outdir, files):
    """
    Parse filepaths for environment, etc., and results files for data.
    """
    # metrics here will be wall time and wrapped time
    p = ps.ProblemSizeParser("lammps")
    count = 0

    # It's important to just parse raw data once, and then use intermediate
    for filename in files:
        dirname = os.path.basename(filename)
        exp = ps.ExperimentNameParser(filename, indir)

        if "/lammps-on-premises/" in filename:
            env_type = "on-premises"
        elif "/lammps-usernetes-toss/" in filename:
            env_type = "usernetes-toss"
        elif "/lammps-with-usernetes-pods/" in filename:
            env_type = "on-premises-usernetes-pods"
        elif "/lammps-with-usernetes/" in filename:
            env_type = "on-premises-usernetes"
        elif "/lammps-usernetes/" in filename:
            env_type = "usernetes"

        exp.env_type = env_type

        # Set the parsing context for the result data frame
        p.set_context(exp.cloud, exp.env, env_type, exp.size)
        exp.show()

        item = ps.read_file(filename)
        problem_size = "16x16x16"
        wall_time = [x for x in item.split("\n") if "Total wall time" in x][0].rsplit(
            " ", 1
        )[-1]
        wall_time = ps.convert_walltime_to_seconds(wall_time)
        cpu_use = float(
            [x for x in item.split("\n") if "CPU use" in x][0]
            .split(" ", 1)[0]
            .replace("%", "")
        )
        p.add_result("duration", wall_time, problem_size)
        p.add_result("cpu_utilization", cpu_use, problem_size)

    print(count)
    print("Done parsing lammps results!")
    p.df.to_csv(os.path.join(outdir, "lammps-reax-results.csv"))

    # Make an image outdir
    img_outdir = os.path.join(outdir, "img")
    if not os.path.exists(img_outdir):
        os.makedirs(img_outdir)

    for metric in ["duration", "cpu_utilization"]:
        fig = plt.figure(figsize=(12, 6))
        gs = plt.GridSpec(1, 3, width_ratios=[2, 0, 0])
        axes = []
        axes.append(fig.add_subplot(gs[0, 0]))

        df = p.df[p.df.metric == metric]
        print(df)

        # fig, axes = plt.subplots(1, 2, sharey=True, figsize=(18, 3.3))
        sns.set_style("whitegrid")
        sns.barplot(
            df,
            ax=axes[0],
            x="nodes",
            y="value",
            hue="env_type",
            hue_order=[
                "on-premises",
                "on-premises-usernetes",
                "on-premises-usernetes-pods",
                "usernetes-toss",
                "usernetes",
            ],
            order=[4, 8, 16, 32],
        )
        title = " ".join([x.capitalize() for x in metric.split("_")])
        axes[0].set_title(f"LAMMPS {title} Problem Size 16x16x16 (CPU)", fontsize=14)
        if metric == "duration":
            axes[0].set_ylabel("Duration (Seconds)", fontsize=14)
        else:
            axes[0].set_ylabel("% CPU Utilization", fontsize=14)
        axes[0].set_xlabel("Nodes", fontsize=14)

        plt.tight_layout()
        plt.savefig(os.path.join(img_outdir, f"lammps-{metric}.png"))
        plt.savefig(os.path.join(img_outdir, f"lammps-{metric}.svg"))
        plt.clf()


def get_columns(command):
    """
    Get columns for data frame depending on command
    """
    # Size       Avg Latency(us)
    if "allreduce" in command:
        return ["size", "avg_latency_us"]
    # Size          Latency (us)
    elif "latency" in command:
        return ["size", "latency_us"]
    # Size      Bandwidth (MB/s)
    return ["size", "bandwidth_mb_s"]


def get_osu_title(slug):
    if slug == "osu_bw":
        title = "OSU Bandwidth"
    elif slug == "osu_latency":
        title = "OSU Latency"
    elif slug == "osu_allreduce":
        title = "OSU AllReduce"
    return title


def parse_and_plot_osu(indir, outdir, files):
    """
    Parse filepaths for environment, etc., and results files for data.
    """
    # metrics here will be wall time and wrapped time
    parsed = []

    # It's important to just parse raw data once, and then use intermediate
    for filename in files:
        item = ps.read_file(filename)
        item = item.strip().split("\n")

        # somaxconn errors
        item = [x for x in item if "somaxconn" not in x and x.strip() != ""]
        command = "osu_allreduce"
        if "osu-bw" in filename:
            command = "osu_bw"
        elif "osu-latency" in filename:
            command = "osu_latency"

        env_type = "on-premises"
        if "osu-usernetes-ucx" in filename:
            env_type = "usernetes-ucx"
        elif "osu-usernetes" in filename:
            env_type = "usernetes"
        elif "osu-with-usernetes" in filename:
            env_type = "on-premises-with-usernetes"

        if "pairs" in filename:
            size = 2
        else:
            size = int(os.path.basename(os.path.dirname(filename)))
        matrix = parse_multi_section([command] + item)
        matrix["context"] = ["corona", "cpu", env_type, size]
        parsed.append(matrix)

    # This is already created
    results = parsed
    ps.write_json(parsed, os.path.join(outdir, "osu-results.json"))
    img_outdir = os.path.join(outdir, "img")

    # Create a data frame for each result type, also lookup by size
    # For osu latency we will combine into one size (2 nodes)
    # Keep gpu and cpu results separate to be conservative
    dfs_cpu = {}
    idxs_cpu = {}

    # lookup for x and y values for each
    lookup_cpu = {}
    for entry in results:
        # The source of truth is the command
        command = entry["command"]

        title = command
        if title not in dfs_cpu:
            dfs_cpu[title] = {}
            idxs_cpu[title] = {}
            lookup_cpu[title] = {}

        size = entry["context"][-1]

        columns = get_columns(title) + [
            "experiment",
            "cloud",
            "env",
            "env_type",
            "nodes",
            "gpu_count",
        ]

        experiment = os.sep.join(entry["context"][:-1] + [command])

        if size not in dfs_cpu[title]:
            dfs_cpu[title][size] = pandas.DataFrame(columns=columns)
            idxs_cpu[title][size] = 0
            lookup_cpu[title][size] = {"x": columns[0], "y": columns[1]}

        # Add command to experiment id since it includes unique command
        for datum in entry["matrix"]:
            dfs_cpu[title][size].loc[idxs_cpu[title][size], :] = (
                datum + [experiment] + entry["context"] + [0]
            )
            idxs_cpu[title][size] += 1

    # Make an output directory for plots by size
    plots_by_size = os.path.join(img_outdir, "by_size")
    if not os.path.exists(plots_by_size):
        os.makedirs(plots_by_size)

    # Save each completed data frame to file and plot!
    slugs = ["osu_latency", "osu_allreduce", "osu_bw"]
    for exp_size in [4, 8, 16, 32]:

        fig = plt.figure(figsize=(19, 3))
        gs = plt.GridSpec(1, 4, width_ratios=[2, 2, 2, 0.8])
        axes = []
        axes.append(fig.add_subplot(gs[0, 0]))
        axes.append(fig.add_subplot(gs[0, 1]))
        axes.append(fig.add_subplot(gs[0, 2]))
        axes.append(fig.add_subplot(gs[0, 3]))
        i = 0

        for slug in slugs:
            sizes = dfs_cpu[slug]
            for size, subset in sizes.items():
                if slug in ["osu_allreduce"] and size != exp_size:
                    continue
                print(f"Preparing plot for {slug} size {size}")

                # Save entire (unsplit) data frame to file
                # subset.to_csv(os.path.join(outdir, f"{slug}-{size}-cpu-dataframe.csv"))

                # Separate x and y - latency (y) is a function of size (x)
                xlabel = "Message size in bytes"
                x = lookup_cpu[slug][size]["x"]
                y = lookup_cpu[slug][size]["y"]

                # for sty in plt.style.available:
                sns.lineplot(
                    data=subset,
                    ax=axes[i],
                    hue="env_type",
                    hue_order=[
                        "on-premises",
                        "usernetes",
                        "usernetes-ucx",
                        "on-premises-with-usernetes",
                    ],
                    x=x,
                    y=y,
                    markers=True,
                    dashes=True,
                    errorbar=("ci", 95),
                )

                title = get_osu_title(slug)
                if slug == "osu_allreduce":
                    title += f" (Size {exp_size})"
                axes[i].set_title(title, fontsize=12)
                axes[i].set_xticklabels(axes[i].get_xmajorticklabels(), fontsize=10)
                axes[i].set_yticklabels(axes[i].get_yticks(), fontsize=12)
                y_label = y.replace("_", " ")
                axes[i].set_xlabel("", fontsize=12)
                axes[i].set_ylabel(y_label + " (logscale)", fontsize=12)
                axes[i].set_xscale("log")
                axes[i].set_yscale("log")
                i += 1

        font_prop = FontProperties(size=14)
        fig.text(
            0.50,
            0.01,
            xlabel + " (logscale)",
            horizontalalignment="center",
            wrap=True,
            fontproperties=font_prop,
        )
        handles, labels = axes[1].get_legend_handles_labels()
        axes[3].legend(
            handles,
            labels,
            loc="center left",
            bbox_to_anchor=(-0.25, 0.5),
            frameon=False,
        )
        for ax in axes[0:3]:
            ax.get_legend().remove()
        axes[3].axis("off")
        plt.xscale("log")
        plt.yscale("log")
        plt.subplots_adjust(bottom=0.15)
        plt.tight_layout()
        plt.savefig(
            os.path.join(plots_by_size, f"osu-latency-bw-reduce-cpu-{exp_size}.png")
        )
        plt.savefig(
            os.path.join(plots_by_size, f"osu-latency-bw-reduce-cpu-{exp_size}.svg")
        )
        plt.clf()
        plt.close()


if __name__ == "__main__":
    main()
