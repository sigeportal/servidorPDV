program ServidorConsole;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  Horse,
  Horse.CORS,
  Horse.Jhonson,
  Horse.HandleException,
  Horse.Logger,
  Horse.Logger.Provider.Console,
  Horse.ServerStatic,
  Horse.GBSwagger,
  UnitComanda.Model in '..\Shared\Model\UnitComanda.Model.pas',
  UnitComplemento.Model in '..\Shared\Model\UnitComplemento.Model.pas',
  Comandas.Controller in '..\Shared\Controllers\Comandas.Controller.pas',
  Complementos.Controller in '..\Shared\Controllers\Complementos.Controller.pas',
  Mesas.Controller in '..\Shared\Controllers\Mesas.Controller.pas',
  Produtos.Controller in '..\Shared\Controllers\Produtos.Controller.pas',
  UnitDatabase in '..\..\..\FormsComuns\Classes\ServidoresUtils\Database\UnitDatabase.pas',
  UnitConstants in '..\..\..\FormsComuns\Classes\ServidoresUtils\Utils\UnitConstants.pas',
  UnitFuncoesComuns.Controller in '..\..\..\FormsComuns\Classes\ServidoresUtils\Utils\UnitFuncoesComuns.Controller.pas',
  UnitFuncoesComuns in '..\..\..\FormsComuns\Classes\ServidoresUtils\Utils\UnitFuncoesComuns.pas',
  UnitFunctions in '..\..\..\FormsComuns\Classes\ServidoresUtils\Utils\UnitFunctions.pas',
  UnitLogin.Controller in '..\..\..\FormsComuns\Classes\ServidoresUtils\Utils\UnitLogin.Controller.pas',
  UnitVendas.Model in '..\Shared\Model\Vendas\UnitVendas.Model.pas',
  UnitVendas.Controller in '..\Shared\Model\Vendas\UnitVendas.Controller.pas',
  UnitVenEst.Model in '..\Shared\Model\VenEst\UnitVenEst.Model.pas',
  UnitOperacoes.Strategy.Interfaces in '..\Shared\Model\Operacoes Strategy\UnitOperacoes.Strategy.Interfaces.pas',
  UnitPedFat.Model in '..\..\..\FormsComuns\Classes\PedFat\UnitPedFat.Model.pas',
  UnitPF_Parcela.Model in '..\..\..\FormsComuns\Classes\PF_Parcela\UnitPF_Parcela.Model.pas',
  UnitTipoPgm.Model in '..\..\..\FormsComuns\Classes\TipoPgm\UnitTipoPgm.Model.pas',
  UnitOperacao.Venda in '..\Shared\Model\Operacoes Strategy\Venda\UnitOperacao.Venda.pas',
  UnitDAV.Model in '..\..\..\FormsComuns\Classes\DAV\UnitDAV.Model.pas',
  UnitProdutos.Model in '..\Shared\Model\Produtos\UnitProdutos.Model.pas',
  UnitHisPro.Model in '..\..\..\FormsComuns\Classes\HisPro\UnitHisPro.Model.pas',
  UnitTotalizador.Model in '..\..\..\FormsComuns\Classes\Totalizadores\UnitTotalizador.Model.pas',
  UnitFaturamento.Model in '..\..\..\FormsComuns\Classes\Faturamentos\UnitFaturamento.Model.pas',
  UnitRecebimentos.Model in '..\..\..\FormsComuns\Classes\Recebimentos\UnitRecebimentos.Model.pas',
  UnitRecPgm.Model in '..\..\..\FormsComuns\Classes\RecPgm\UnitRecPgm.Model.pas',
  UnitMovimentacoes.Model in '..\..\..\FormsComuns\Classes\Movimentacoes\UnitMovimentacoes.Model.pas',
  UnitCaixa.Model in '..\..\..\FormsComuns\Classes\Caixa\UnitCaixa.Model.pas',
  UnitNiveis.Model in '..\Shared\Model\Niveis\UnitNiveis.Model.pas',
  UnitClientes.Model in '..\Shared\Model\Clientes\UnitClientes.Model.pas',
  UnitClientes.Controller in '..\Shared\Model\Clientes\UnitClientes.Controller.pas',
  UnitVeAdicionais.Model in '..\Shared\Model\VeAdicionais\UnitVeAdicionais.Model.pas',
  UnitVeOpcoes.Model in '..\Shared\Model\VeOpcoes\UnitVeOpcoes.Model.pas',
  UnitEmpresa.Model in '..\..\..\FormsComuns\Classes\Empresa\UnitEmpresa.Model.pas',
  UnitEmpresa.Controller in '..\..\..\FormsComuns\Classes\Empresa\UnitEmpresa.Controller.pas',
  UnitControleSenhas.Controller in '..\Shared\Controllers\UnitControleSenhas.Controller.pas',
  UnitDataset.Controller in '..\..\..\FormsComuns\Classes\ServidoresUtils\Utils\UnitDataset.Controller.pas',
  UnitCpAdicionais.Model in '..\Shared\Model\CpAdicionais\UnitCpAdicionais.Model.pas',
  UnitCpOpcoes.Model in '..\Shared\Model\CpOpcoes\UnitCpOpcoes.Model.pas';

var
	LLogFileConfig: THorseLoggerConsoleConfig;

begin
	// ReportMemoryLeaksOnShutdown := True;
	LLogFileConfig := THorseLoggerConsoleConfig.New.SetLogFormat('${request_clientip} [${time}] ${response_status}');
	try
		THorseLoggerManager.RegisterProvider(THorseLoggerProviderConsole.New());
		// middlewares
		THorse.Use(CORS);
		THorse.Use(Jhonson);
		THorse.Use(THorseLoggerManager.HorseCallback);
		THorse.Use(HandleException);
		THorse.Use(ServerStatic('site'));
		THorse.Use(HorseSwagger); // Access http://localhost:9000/swagger/doc/html

				// Inicio setup Documentacao
				Swagger
					.BasePath('v1')
					.Info
						.Title('Servidor PDV Lanchonetes')
						.Description('API Horse para o Sistema de PDV Lanchoentes')
						.Contact
							.Name('Portal.com')
							.Email('portalsoft.com@gmail.com')
							.URL('http://www.portalsoft.net.br')
						.&End
					.&End
				.&End;

		// Controllers
		TDatasetController.Router;
		TLoginController.Router;
		TMesasController.Registrar;
		TComandasController.Registrar;
		TProdutosController.Registrar;
		TComplementosController.Registrar;
		TFuncoesComunsController.Router;
		TVendasController.Router;
		TClientesController.Router;
		TEmpresaController.Router;
		TControleSenhasController.Router;

		// start server
		THorse.Listen(9000,
			procedure
			begin
				Writeln('Servidor rodando na porta', ': ', THorse.Port.ToString);
				Readln;
			end);
	finally
		LLogFileConfig.Free;
	end;

end.
