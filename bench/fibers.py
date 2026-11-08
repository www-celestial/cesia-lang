# COUNT asyncio tasks park on one event, then all end once it is set.
import asyncio, sys

async def main(count):
    gate = asyncio.Event()
    async def task():
        await gate.wait()
    tasks = [asyncio.create_task(task()) for _ in range(count)]
    await asyncio.sleep(0)
    gate.set()
    await asyncio.gather(*tasks)
    print(count)

asyncio.run(main(int(sys.argv[1])))
