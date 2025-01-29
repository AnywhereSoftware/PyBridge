import asyncio
from asyncio import Queue, StreamReader, StreamWriter
from typing import List, Tuple

from b4x_bridge.b4x_serializator import B4XSerializator
from b4x_bridge.bridge import B4XBridge, Task, PyObject, TaskType, task_done_callback


class CommManager:
    def __init__(self, bridge: B4XBridge, port: int):
        self.bridge = bridge
        self.serializator = B4XSerializator(types=[Task, PyObject])
        self.port = port
        self.read_queue: Queue[List[Task]] = Queue()
        self.write_queue: Queue[Task] = Queue()
        self.writer = None

    async def connect(self):
        print("Connecting to port: {}".format(self.port))
        reader, writer = await asyncio.open_connection("127.0.0.1", self.port)
        self.writer = writer
        asyncio.create_task(self.reader_loop(reader)).add_done_callback(task_done_callback)
        asyncio.create_task(self.writer_loop(writer)).add_done_callback(task_done_callback)

    async def reader_loop(self, reader: StreamReader):
        while True:
           length: bytes = await reader.readexactly(4)
           n = int.from_bytes(length, 'big')
           data = await reader.readexactly(n)
           flat_tasks: List = self.serializator.convert_bytes_to_object(data)
           tasks = []
           for i in range(0, len(flat_tasks), 3):
                tasks.append(Task(id=flat_tasks[i], task_type=TaskType(flat_tasks[i+1]), extra=flat_tasks[i+2]))
           self.read_queue.put_nowait(tasks)

    async def writer_loop(self, writer: StreamWriter):
        while True:
            task = await self.write_queue.get()
            data = self.serializator.convert_object_to_bytes(task.to_tuple())
            prefix: bytes = len(data).to_bytes(length=4, byteorder='big')
            writer.write(prefix)
            writer.write(data)

    async def close(self):
        if self.writer:
            self.writer.close()
            await self.writer.wait_closed()