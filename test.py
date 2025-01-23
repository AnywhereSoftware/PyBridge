import asyncio

import b4x_bridge

class Test:
    def __init__(self):
        self.n1 = 10
        self.n2 = 20

    def sum(self, x, y) -> int:
        return x + y

    async def sum2(self, x, y) -> int:
        for _ in range(10):
            await asyncio.sleep(0.3)
        return x * y


