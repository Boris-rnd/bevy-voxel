# Simple utility to add some wesl features to wgsl
# I want to add include! in wgsl, and I can't make wesl work nicely (crashes even though I have hot reloading + not pretty errors)

from sys import argv
from watchdog.observers import Observer
from watchdog.events import *
import os,sys,time
def main():
    if len(argv) < 2:
        print("Usage: python compile.py <path_to_wgsl_file>")
        return

    wgsl_file = argv[1]
    compile_wgsl(wgsl_file)
    
    print(f"Watching {os.path.dirname(wgsl_file)} for changes...")
    event_handler = FileSystemEventHandler()
    observer = Observer()
    observer.schedule(event_handler, os.path.dirname(wgsl_file), recursive=True)
    observer.start()
    event_handler.on_modified = on_modified(wgsl_file)
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()

def on_modified(wgsl_file):
    def on_modified_inner(event: FileModifiedEvent):
        if (event.src_path.endswith('-compiled.wgsl')) or (not event.src_path.endswith('.wgsl')) or (event.is_directory):return
        # print(event.event_type, event.is_synthetic, event)
        print(f"File {event.src_path} modified, recompiling..."),
        compile_wgsl(wgsl_file)
    return on_modified_inner
    

def compile_wgsl(file: str):
    if not os.path.exists(file):
        print(f"File {file} does not exist.")
        sys.exit(1)

    output_file = file.replace('.wgsl', '-compiled.wgsl')
    formatted_content = format_doc(file)
    
    with open(output_file, 'w') as f:
        f.write(formatted_content)
    
    print(f"Compiled {file} to {output_file}")


def format_doc(file: str) -> str:
    
    if not os.path.exists(file):
        print(f"File {file} does not exist.")
        sys.exit(1)

    print(f"Compiling {file}...")
    with open(os.path.abspath(file), 'r') as file:
        content = file.read()
    lines = content.splitlines()
    new_lines = []
    for line in lines:
        if line.startswith("include!"):

            new_lines.append(format_doc(line[9:].strip()))
        else:
            new_lines.append(line)
    return "\n".join(new_lines)


if __name__ == "__main__":
    main()
