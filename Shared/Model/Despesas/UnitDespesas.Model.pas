unit UnitDespesas.Model;

interface

uses
  {$IFDEF PORTALORM}
  UnitPortalORM.Model,
  {$ELSE}
  UnitBancoDeDados.Model,
  {$ENDIF}
  System.SysUtils;

type
  [TRecursoServidor('/despesas')]
  TDespesaLancamento = class(TTabela)
  private
    FCodigo: Integer;
    FSubDespesa: Integer;
    FSubDespesaNome: string;
    FValor: Currency;
    FData: TDateTime;
    FDocumento: string;
    FHistorico: string;
    FFuncionario: Integer;
    FPDV: Integer;
    FConta: Integer;
    FTipoPagamento: string;
    FCaixa: Integer;
    FFatura2: Integer;
    FPagamento: Integer;
    FMovimentacao: Integer;
  public
    property Codigo: Integer read FCodigo write FCodigo;
    property SubDespesa: Integer read FSubDespesa write FSubDespesa;
    property SubDespesaNome: string read FSubDespesaNome write FSubDespesaNome;
    property Valor: Currency read FValor write FValor;
    property Data: TDateTime read FData write FData;
    property Documento: string read FDocumento write FDocumento;
    property Historico: string read FHistorico write FHistorico;
    property Funcionario: Integer read FFuncionario write FFuncionario;
    property PDV: Integer read FPDV write FPDV;
    property Conta: Integer read FConta write FConta;
    property TipoPagamento: string read FTipoPagamento write FTipoPagamento;
    property Caixa: Integer read FCaixa write FCaixa;
    property Fatura2: Integer read FFatura2 write FFatura2;
    property Pagamento: Integer read FPagamento write FPagamento;
    property Movimentacao: Integer read FMovimentacao write FMovimentacao;
  end;

implementation

end.
