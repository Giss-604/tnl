#!/usr/bin/env python3

# git add, commit and push in one go.
# https://codeberg.org/anhsirk0/gacp-py

import os
import sys
import subprocess
import argparse
import re
from dataclasses import dataclass
from typing import List


class Color:
    BLUE = '\33[94m'
    CYAN = '\033[96m'
    ENDC = '\033[0m'
    GREEN = '\033[92m'
    GREY = '\33[90m'
    MAGENTA = '\33[95m'
    RED = '\033[91m'
    YELLOW = '\33[33m'


class Status:
    ADDED = 'A'
    MODIFIED = 'M'
    DELETED = 'D'
    NEW = '??'


@dataclass
class GitFile:
    status: Status
    abs_path: str
    rel_path: str


TOP_LEVEL: str = ''
ADDED: List[GitFile] = []
EXCLUDED: List[GitFile] = []
MAX_COLS: int = 30
USE_EDITOR_MSG: str = 'GACP_USE_EDITOR'
COMMIT_MESSAGE: str = os.getenv('GACP_DEFAULT_MESSAGE', USE_EDITOR_MSG)


def colored(text: str, color: Color) -> str:
    """
    Returns colored text
    @param text as str
    @param color as Color
    @return str
    """
    return f'{color}{text}{Color.ENDC}'


def inside_a_git_repo() -> bool:
    """
    Returns True if `cwd` is inside a git repository else False
    @return bool
    """
    try:
        out: bytes = subprocess.check_output(
            ['git', 'rev-parse', '--is-inside-work-tree'],
            stderr=subprocess.DEVNULL
        )
        return out.decode('utf-8').rstrip() == 'true'
    except subprocess.CalledProcessError:
        return False


def get_top_level() -> str:
    """
    Returns the repository's root directory
    @return str
    """
    try:
        out: bytes = subprocess.check_output(
            ['git', 'rev-parse', '--show-toplevel'],
            stderr=subprocess.DEVNULL
        )
        return out.decode('utf-8').rstrip()
    except subprocess.CalledProcessError:
        return ''


def get_data_dir() -> str:
    """
    Returns config dir, like `~/.config` on posix
    @return as str
    """
    data_dir: str = ''
    if os.name == 'nt':
        data_dir = os.getenv('APPDATA', '')
    elif os.name == 'posix':
        data_dir = os.getenv('XDG_DATA_HOME', os.getenv('XDG_CONFIG_HOME', ''))

    if not data_dir:
        if not (home := os.getenv('HOME')):
            return ''
        data_dir = os.path.join(home, '.config')

    if not data_dir:
        return ''

    data_dir = os.path.join(data_dir, 'gacp')
    return data_dir


def get_auto_excluded_files() -> List[str]:
    """
    Read gacp.exclude file and return file_paths
    @return List[str]
    """
    auto_excluded_files: List[str] = []
    data_dir: str = get_data_dir()
    repo_name: str = TOP_LEVEL.split(os.path.sep)[-1]
    config_file: str = os.path.join(data_dir, 'gacp.exclude')

    if not os.path.isfile(config_file):
        return []

    # else read config file
    with open(config_file, 'r') as config:
        comments_rgx = re.compile('\#.*')
        for line in config:
            line = comments_rgx.sub('', line.rstrip().lstrip())
            if not TOP_LEVEL in line:
                continue
            line = re.sub(r'^.*=', '', line)
            line = re.sub(r',\s+', ',', line)
            line = re.sub(r',+', ',', line)
            line = re.sub(r'(^,|,$)', '', line.lstrip())
            try:
                auto_excluded_files = [
                    os.path.join(TOP_LEVEL, path) for path in line.split(",")
                ]
            except:
                break
            break
    return auto_excluded_files


def get_files_inside_dir(dir_path: str) -> List[str]:
    """
    Returns all files (recursively) inside of `dir_path`
    @param dir_path as str
    @return List[str]
    """
    return [
        os.path.join(parent, f)
        for parent, _, files in os.walk(dir_path)
        for f in files
    ]


def to_git_file(status: Status, abs_path: str, rel_path: str) -> GitFile:
    """
    Return a GitFile
    @param status as Status
    @param abs_path as str
    @param rel_path as str
    @return GitFile
    """
    if ' ' in abs_path:
        abs_path = '"' + abs_path + '"'
    if ' ' in rel_path:
        rel_path = '"' + rel_path + '"'

    return GitFile(status, abs_path, rel_path)


def to_empty_git_file(file_path: str) -> GitFile:
    """
    Returns a GitFile thats is not from git_status
    Used to transform files in args to GitFiles
    @param file_path as str
    @return GitFile
    """
    return GitFile(
        Status.NEW,  # Status here does not matter
        os.path.abspath(
            file_path.replace(f':{os.path.sep}:', TOP_LEVEL + os.path.sep)
        ),
        file_path
    )


def to_git_path(path: str, relative: bool) -> str:
    """
    Returns relative path in git notation (like ':/src/main.py')
    if `relative` is True, returns the path relative to `cwd`
    @param path as str
    @param relative as bool
    @return str
    """
    rel_path: str = os.path.relpath(path)
    # path relative to toplevel in git style
    if relative:
        return rel_path

    rel_path_to_top_level: str = os.path.relpath(path, TOP_LEVEL)
    if rel_path.startswith('..' + os.path.sep):
        rel_path = f':{os.path.sep}:{rel_path_to_top_level}'
    return rel_path


def parse_git_status(git_status: str, relative: bool = True) -> List[GitFile]:
    """
    Parse git_status line by line,
    Returns a list of GitFile
    if any path is a directory, this func will adds all its files recursively
    relative paths are relative to TOP_LEVEL unless `relative` if True
    @param git_status as str
    @param relative as bool
    @return List[Gitfile]
    """
    git_files: List[GitFile] = []
    for line in git_status.split('\n'):
        try:
            status, file_path = line.lstrip().split()
        except ValueError:
            try:
                # filename has spaces
                splitted = line.lstrip().split(' ')
                status = splitted[0]
                file_path = ' '.join(splitted[1:])
            except ValueError:
                continue
        file_path = file_path.replace('"', '')
        abs_path = os.path.join(TOP_LEVEL, file_path)
        rel_path = to_git_path(abs_path, relative)
        if os.path.isdir(abs_path):
            for f in get_files_inside_dir(abs_path):
                git_files.append(
                    to_git_file(status, f, to_git_path(f, relative))
                )
        else:
            git_files.append(to_git_file(status, abs_path, rel_path))
    return git_files


def is_file_in(arr: List[GitFile], git_file: GitFile) -> bool:
    """
    Returs if a `git_file` is in `arr` of GitFile
    @param arr as List[GitFile]
    @param git_file as GitFile
    @return bool
    """
    git_file_abs_path = git_file.abs_path
    if ' ' in git_file_abs_path:
        git_file_abs_path = git_file_abs_path.replace('"', '')
    for f in arr:
        abs_path = f.abs_path
        if ' ' in abs_path:
            abs_path = abs_path.replace('"', '')
        if abs_path == git_file_abs_path:
            return True
        if git_file_abs_path.startswith(abs_path + os.path.sep):
            return True
    return False


def get_added_excluded_files(
        git_files: List[GitFile]) -> (List[GitFile], List[GitFile]):
    """
    Returns tuple of files to add and files to exclude
    This function also updates `MAX_COLS`
    @param git_files as List[GitFile]
    @param added as List[str]
    @param excludes as List[str]
    """
    global MAX_COLS
    global ADDED
    files_to_add: List[GitFile] = []
    files_to_exclude: List[GitFile] = []
    for f in git_files:
        if (max_cols := len(str(f.rel_path))) > MAX_COLS:
            MAX_COLS = max_cols
        if is_file_in(EXCLUDED, f):
            files_to_exclude.append(f)
            continue
        if is_file_in(ADDED, f) or ADDED[0].abs_path == TOP_LEVEL:
            files_to_add.append(f)
    return (files_to_add, files_to_exclude)


def get_git_status():
    try:
        out: bytes = subprocess.check_output(
            ['git', 'status', '--porcelain'],
            stderr=subprocess.DEVNULL
        )
        return out.decode('utf-8').rstrip()
    except subprocess.CalledProcessError:
        return ''


def git_add_commit_push(files_to_add: List[GitFile], no_push: bool = False):
    """
    git add the `files_to_add` and commit
    unless `no_push` run git push
    @param files_to_add as List[GitFile]
    @param no_push as bool
    """
    print()
    added_files: List[str] = [f.rel_path for f in files_to_add]
    commit_cmd: List[str] = ['git', 'commit']
    if COMMIT_MESSAGE != USE_EDITOR_MSG:
        commit_cmd += ['-m', COMMIT_MESSAGE]

    try:
        retcode: int = subprocess.call(['git', 'add'] + added_files)
        if retcode != 0:
            return
        retcode = subprocess.call(commit_cmd)
        if retcode != 0 or no_push:
            return
        retcode = subprocess.call(['git', 'push'])
        if retcode != 0:
            return
    except subprocess.CalledProcessError:
        return


def print_git_file(git_file: GitFile, idx: int,
                   color: Color = None, max_count: int = 5):
    """
    Prints a git_file.rel_path in color
    @param git_file as GitFile
    @param idx as int
    @param color as Color
    @param max_count as int
    """
    color, label = {
        Status.ADDED: (color or Color.MAGENTA, 'staged'),
        Status.NEW: (color or Color.CYAN, 'new'),
        Status.MODIFIED: (color or Color.GREEN, 'modified'),
        Status.DELETED: (color or Color.RED, 'deleted'),
    }.get(git_file.status, (color or Color.GREY, git_file.status))
    fmt: str = '{:>' + str(max_count + 5) + '}) {:' + \
        str(MAX_COLS) + '} {:>12}'
    print(colored(fmt.format(idx, git_file.rel_path, f'({label})'), color))


def get_heading(title: str, total: int) -> str:
    """
    Returns heading for a section using `title` & `total`
    @param title as str
    @param total as int
    @return str
    """
    suffix = 's' if total > 1 else ''
    return f'{title} ({total} file{suffix}):'


def parse_arguments() -> argparse.Namespace:
    """
    Parse CLI Args and returns parsed arguments
    @return argparse.Namespace
    """
    parser = argparse.ArgumentParser()
    parser.add_argument('message', metavar='MESSAGE', type=str, nargs='?',
                        default=COMMIT_MESSAGE, help='Commit message')
    parser.add_argument('-f', '--files', metavar='FILE', type=str, nargs='+',
                        help='Files to add (git add)')
    parser.add_argument('-e', '--exclude', metavar='FILE', type=str, nargs='+',
                        help='Files to exclude (not to git add)')
    parser.add_argument('-d', '--dry-run', action='store_true',
                        help='Show what will happen')
    parser.add_argument('-l', '--list', action='store_true',
                        help='List files that can be added/excluded'),
    parser.add_argument('-r', '--relative', action='store_true',
                        help='Enable relative paths to cwd'),
    parser.add_argument('-ni', '--no-ignore', action='store_true',
                        help='Do not auto exclude files from gacp ignore file'),
    parser.add_argument('-np', '--no-push', action='store_true',
                        help='No push (Only add and commit)'),
    return parser.parse_args()


def main():
    global TOP_LEVEL
    global ADDED
    global EXCLUDED
    global COMMIT_MESSAGE

    args = parse_arguments()

    if not inside_a_git_repo():
        print('Not a git repository.')
        sys.exit(1)

    TOP_LEVEL = get_top_level()
    COMMIT_MESSAGE = args.message

    excluded_files = args.exclude or []
    if not args.no_ignore:
        excluded_files += [
            os.path.relpath(f) for f in get_auto_excluded_files()
        ]

    ADDED = [to_empty_git_file(f) for f in args.files or [f':{os.path.sep}:']]
    EXCLUDED = [to_empty_git_file(f) for f in excluded_files]

    parsed_git_status: List[GitFile] = parse_git_status(get_git_status(),
                                                        args.relative)

    if args.list:
        for f in parsed_git_status:
            print(f.rel_path)
        sys.exit(0)

    if len(parsed_git_status) == 0:
        print("Nothing to add")
        sys.exit(0)

    files_to_add, files_to_exclude = get_added_excluded_files(
        parsed_git_status)

    if (total_added := len(files_to_add)) > 0:
        print(colored(get_heading('Added', total_added), Color.GREY))
        for idx, f in enumerate(files_to_add):
            print_git_file(f, idx + 1, max_count=len(str(total_added)))
        print()

    if (total_excluded := len(files_to_exclude)) > 0:
        print(colored(get_heading('Excluded', total_excluded), Color.GREY))
        for idx, f in enumerate(files_to_exclude):
            print_git_file(f, idx + 1, Color.YELLOW,
                           max_count=len(str(total_added)))
        print()

    if COMMIT_MESSAGE != USE_EDITOR_MSG:
        print(colored('Commit message:', Color.GREY))
        print(colored(' ' * 5 + f'{COMMIT_MESSAGE}', Color.BLUE))

    if args.dry_run:
        sys.exit(0)

    if total_added == 0:
        print(colored('\nNo files added', Color.RED))
        sys.exit(1)

    git_add_commit_push(files_to_add, args.no_push)


if __name__ == '__main__':
    main()
