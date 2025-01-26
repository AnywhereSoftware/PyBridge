import asyncio
import builtins
import importlib
import sys
from dataclasses import dataclass
from enum import IntEnum
from typing import Tuple, List, Optional

from b4x_bridge.b4x_serializator import B4XSerializator


@dataclass(frozen=True, slots=True)
class PyObject:
    Key: int

class TaskType(IntEnum):
    RUN = 1
    GET = 2
    RUN_ASYNC = 3
    CLEAN = 4
    ERROR = 5


@dataclass(slots=True, frozen=True)
class Task:
    id: int
    task_type: TaskType
    extra: list
    def to_tuple(self) -> Tuple:
        return self.id, self.task_type.value, self.extra

    def get_store_key(self) -> int:
        return self.extra[4]

    @classmethod
    def return_value_task (cls, _id: int, value) -> "Task":
        task_type = TaskType.RUN
        if isinstance(value, Exception):
            task_type = TaskType.ERROR
            value = str(value)
        if not B4XSerializator.is_serializable(value):
            value = f"Unserializable object ({type(value).__name__})"
        return Task(id=_id, task_type=task_type, extra=[value])

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

    def unwrap_list(self, _list: List):
        for i in range(len(_list)):
            obj = _list[i]
            if isinstance(obj, PyObject):
                _list[i] = self.memory[obj.Key]
            elif isinstance(obj, dict):
                self.unwrap_dict(obj)
            elif isinstance(obj, list):
                self.unwrap_list(obj)
            elif isinstance(obj, tuple):
                _list[i] = self.unwrap_tuple(obj)

    def unwrap_dict(self, _dict: dict):
        keys_that_are_unwrapped = []
        for k, v in _dict.items():
            if isinstance(v, PyObject):
                keys_that_are_unwrapped.append(k)
            elif isinstance(v, dict):
                self.unwrap_dict(v)
            elif isinstance(v, list):
                self.unwrap_list(v)
            elif isinstance(v, tuple):
                keys_that_are_unwrapped.append(k)
        for k in keys_that_are_unwrapped:
            v = _dict[k]
            if isinstance(v, PyObject):
                _dict[k] = self.memory[v.Key]
            if isinstance(v, tuple):
                _dict[k] = self.unwrap_tuple(v)

    def unwrap_tuple(self, _tuple: tuple) -> tuple:
        _list = list(_tuple)
        self.unwrap_list(_list)
        return tuple(_list)

    def run(self, task: Task) -> Tuple[bool, Optional[Exception]]:
        target, method_name, args, kwargs, store_target = task.extra
        target = self.memory[target]
        self.unwrap_list(args)
        self.unwrap_dict(kwargs)
        try:
            method = getattr(target, method_name)
            res = method(*args, **kwargs)
            self.memory[store_target] = res
            return True, None
        except Exception as e:
            e = self.wrap_exception(target, method_name, e)
            self.memory[store_target] = e
            return False, e

    async def run_async(self, task: Task, error: Optional[Exception]):
        target, method_name, args, kwargs, store_target = task.extra
        target = self.memory[target]
        self.unwrap_list(args)
        self.unwrap_dict(kwargs)
        if error is not None:
            res = error
        else:
            try:
                method = getattr(target, task.extra[1])
                res = await method(*args, **kwargs)
            except Exception as e:
                res = self.wrap_exception(target, task.extra[1], e)
        self.memory[store_target] = res
        self.comm.write_queue.put_nowait(Task.return_value_task(task.id, res))

    def get_pyobject(self, task: Task):
        object_id = task.extra[0]
        obj = self.memory[object_id]
        self.comm.write_queue.put_nowait(Task.return_value_task(task.id, obj))

    def clean(self, task: Task):
        for key in task.extra:
            if key in self.memory:
                del self.memory[key]

    def wrap_exception(self, target, method, exception) -> Exception:
        e = Exception(f"Python Error ({type(exception).__name__}) - Method: {type(target).__name__}.{method}: {exception}")
        print(e)
        return e

    async def wait_for_incoming(self):
        while True:
            tasks: List[Task] = await self.comm.read_queue.get()
            state_good = True
            e: Optional[Exception] = None
            for task in tasks:
                # print(task)
                if task.task_type == TaskType.RUN:
                    if not state_good:
                        self.memory[task.get_store_key()] = e
                    else:
                        state_good, e = self.run(task)
                elif task.task_type == TaskType.GET:
                    self.get_pyobject(task)
                elif task.task_type == TaskType.RUN_ASYNC:
                    asyncio.create_task(self.run_async(task, e))
                elif task.task_type == TaskType.CLEAN:
                    self.clean(task)

    def kill(self):
        sys.exit()

def exception_handler(loop, context):
    print(context)

async def main():
    bridge = B4XBridge()
    loop = asyncio.get_event_loop()
    loop.set_exception_handler(exception_handler)
    await bridge.start()
    await bridge.wait_for_incoming()




