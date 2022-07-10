import { expect } from 'chai';
import { ContractReceipt, ContractTransaction, Event } from 'ethers';
import { Result } from 'ethers/lib/utils';

import { TypedEvent } from '../types/common';

function eventArg(name: string, receipt: ContractReceipt): unknown {
  const found = eventsArg(name, receipt);
  expect(found.length, 'Only one event expected').equals(1);
  return found[0];
}

function eventsArg(name: string, receipt: ContractReceipt): unknown[] {
  const availableEvents = receiptEvents(receipt);
  const found: Result[] = [];

  for (let i = 0; i < availableEvents.length; i++) {
    if (availableEvents[i]?.event === name) {
      // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
      found.push(availableEvents[i].args!);
    }
  }

  expect(found.length, `Failed to find any event matching name: ${name}`).is.greaterThan(0);

  return found;
}

function receiptEvents(receipt: ContractReceipt): Event[] {
  // eslint-disable-next-line no-unused-expressions
  expect(receipt.events, 'No receipt events').is.not.undefined;
  const availableEvents = receipt.events;
  // eslint-disable-next-line no-unused-expressions
  expect(availableEvents, 'Receipt events are undefined').is.not.undefined;
  return availableEvents || [];
}

export type ContractReceiptSource =
  | ContractReceipt
  | Promise<ContractReceipt>
  | ContractTransaction
  | Promise<ContractTransaction>;

export interface EventFactory<TArgObj = unknown> {
  one<Result = TArgObj>(receipt: ContractReceipt, fn?: (args: TArgObj) => Result): Result;
  many<Result = TArgObj>(receipt: ContractReceipt, fn?: (args: TArgObj) => Result): Result[];

  waitOne<Result = TArgObj>(source: ContractReceiptSource, fn?: (args: TArgObj) => Result): Promise<Result>;
  waitMany<Result = TArgObj>(source: ContractReceiptSource, fn?: (args: TArgObj) => Result): Promise<Result[]>;

  waitOneWithReceipt<Result = TArgObj>(
    source: ContractReceiptSource,
    fn?: (args: TArgObj) => Result
  ): Promise<{ result: Result; receipt: ContractReceipt }>;

  waitManyWithReceipt<Result = TArgObj>(
    source: ContractReceiptSource,
    fn?: (args: TArgObj) => Result
  ): Promise<{ result: Result[]; receipt: ContractReceipt }>;

  chainOne(source: ContractReceiptSource, fn: (args: TArgObj) => void): Promise<ContractReceipt>;
  chainMany(source: ContractReceiptSource, fn: (args: TArgObj) => void): Promise<ContractReceipt>;

  toString(): string;
  name(): string | undefined;
}

async function receiptOf(av: ContractReceiptSource): Promise<ContractReceipt> {
  const v = await av;
  return 'gasUsed' in v ? v : v.wait(1);
}

const nameByFactory = new Map<EventFactory, string>();

export const wrap = <TArgList extends unknown[], TArgObj>(
  template: TypedEvent<TArgList, TArgObj>, // only for type
  customName?: string
): EventFactory<TArgObj> =>
  new (class implements EventFactory<TArgObj> {
    one<Result = TArgObj>(receipt: ContractReceipt, fn?: (args: TArgObj) => Result): Result {
      const arg = eventArg(this.toString(), receipt) as TArgObj;
      if (fn === undefined) {
        return arg as unknown as Result;
      }
      return fn(arg);
    }

    many<Result = TArgObj>(receipt: ContractReceipt, fn?: (args: TArgObj) => Result): Result[] {
      const args = eventsArg(this.toString(), receipt) as TArgObj[];
      if (fn === undefined) {
        return args as unknown[] as Result[];
      }

      const result: Result[] = [];
      args.forEach((v) => result.push(fn(v)));
      return result;
    }

    async waitOne<Result = TArgObj>(source: ContractReceiptSource, fn?: (args: TArgObj) => Result): Promise<Result> {
      const receipt = await receiptOf(source);
      return this.one(receipt, fn);
    }

    async waitMany<Result = TArgObj>(source: ContractReceiptSource, fn?: (args: TArgObj) => Result): Promise<Result[]> {
      const receipt = await receiptOf(source);
      return this.many(receipt, fn);
    }

    async waitOneWithReceipt<Result = TArgObj>(
      source: ContractReceiptSource,
      fn?: (args: TArgObj) => Result
    ): Promise<{ result: Result; receipt: ContractReceipt }> {
      const receipt = await receiptOf(source);
      return { result: this.one(receipt, fn), receipt } as const;
    }

    async waitManyWithReceipt<Result = TArgObj>(
      source: ContractReceiptSource,
      fn?: (args: TArgObj) => Result
    ): Promise<{ result: Result[]; receipt: ContractReceipt }> {
      const receipt = await receiptOf(source);
      return { result: this.many(receipt, fn), receipt } as const;
    }

    async chainOne(source: ContractReceiptSource, fn: (args: TArgObj) => void): Promise<ContractReceipt> {
      const receipt = await receiptOf(source);
      this.one(receipt, fn);
      return receipt;
    }

    async chainMany(source: ContractReceiptSource, fn: (args: TArgObj) => void): Promise<ContractReceipt> {
      const receipt = await receiptOf(source);
      this.many(receipt, fn);
      return receipt;
    }

    toString(): string {
      return this.name() ?? 'unknown';
    }

    name(): string | undefined {
      return customName ?? nameByFactory.get(this);
    }
  })();

export const addNamedEvent = (f: EventFactory, name: string): void => {
  nameByFactory.set(f, name);
};
