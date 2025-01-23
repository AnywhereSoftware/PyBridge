import asyncio
import builtins
import importlib
import sys
from dataclasses import dataclass
from enum import IntEnum
from typing import Tuple, List


@dataclass(frozen=True, slots=True)
class PyObject:
    Key: int

class TaskType(IntEnum):
    RUN = 1
    GET = 2
    RUN_ASYNC = 3
    CLEAN = 4


@dataclass(frozen=True, slots=True)
class Task:
    id: int
    task_type: TaskType
    extra: list

    def to_tuple(self) -> Tuple:
        return self.id, self.task_type.value, self.extra

    @staticmethod
    def from_tuple(t: Tuple) -> "Task":
        return Task(t[0], TaskType(t[1]), t[2])

class B4XBridge:
    def __init__(self):
        self.memory:dict[int, object] = {
            1: self,
            2: importlib,
            3: builtins
        }
        from comm_manager import CommManager
        self.comm = CommManager(self, int(sys.argv[1]))


    async def start(self):
        await self.comm.connect()


    def run(self, task: Task):
        target, args, kwargs = self.replace_pyobjects(task)
        method = getattr(target, task.extra[1])
        store_target: PyObject = task.extra[4]
        res = method(*args, **kwargs)
        self.memory[store_target.Key] = res

    async def run_async(self, task: Task):
        target, args, kwargs = self.replace_pyobjects(task)
        method = getattr(target, task.extra[1])
        store_target: PyObject = task.extra[4]
        res = await method(*args, **kwargs)
        self.memory[store_target.Key] = res
        self.comm.write_queue.put_nowait(task)

    def get_pyobject(self, task: Task):
        object_ids: List[int] = task.extra
        res = [self.memory[_id] for _id in object_ids]
        self.comm.write_queue.put_nowait(Task(task.id, task.task_type, res))

    def replace_pyobjects(self, task: Task) -> Tuple:
        target, args, kwargs = task.extra[0], task.extra[2], task.extra[3]
        target = self.memory[target.Key]
        args = [self.memory[k.Key] if isinstance(k, PyObject) else k for k in args]
        kwargs = {k: self.memory[v.Key] if isinstance(v, PyObject) else v for k, v in kwargs.items()}
        return target, args, kwargs

    def clean(self, task: Task):
        print("cleaning", len(task.extra))
        for key in task.extra:
            del self.memory[key]

    async def wait_for_incoming(self):
        while True:
            task: Task = await self.comm.read_queue.get()
            # print(task)
            if task.task_type == TaskType.RUN:
                self.run(task)
            elif task.task_type == TaskType.GET:
                self.get_pyobject(task)
            elif task.task_type == TaskType.RUN_ASYNC:
                asyncio.create_task(self.run_async(task))
            elif task.task_type == TaskType.CLEAN:
                self.clean(task)

    def kill(self):
        sys.exit()


async def main():
    bridge = B4XBridge()
    await bridge.start()
    await bridge.wait_for_incoming()




