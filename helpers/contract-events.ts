import { ApplicationSubmittedEvent } from '../types/contracts/governance/ApprovalCatalog';
import { ProxyCreatedEvent } from '../types/contracts/governance/ProxyCatalog';
import { TokenSwappedEvent } from '../types/contracts/premium/mocks/MockBalancerLib2';
import { TransferEvent } from '../types/contracts/tools/tokens/ERC20Base';

import { addNamedEvent, EventFactory, wrap } from './event-wrapper';

const stub = null as unknown;

export const Events = {
  TokenSwapped: wrap(stub as TokenSwappedEvent),
  ProxyCreated: wrap(stub as ProxyCreatedEvent),
  Transfer: wrap(stub as TransferEvent),
  ApplicationSubmitted: wrap(stub as ApplicationSubmittedEvent),
};

Object.entries(Events).forEach(([name, factory]) => addNamedEvent(factory, name));

export const eventByName = (s: string): EventFactory => Events[s] as EventFactory;
